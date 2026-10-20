import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

/// Deterministic IDs derived from each table's natural key.
///
/// Two devices that create the same deck, word, meaning or card while offline
/// get the same primary key, so sync merges them instead of colliding on the
/// UNIQUE natural-key constraints.
abstract final class Ids {
  static const _uuid = Uuid();
  static const _namespace = '8a3c5e1e-7d4b-5b8e-9f0a-6c2d1e4b7a90';
  static String _v5(List<Object> parts) =>
      _uuid.v5(_namespace, jsonEncode(parts));

  static String deck(String deckKey) => _v5(['deck', deckKey]);
  static String entry(String normalizedTerm, String source, String target) =>
      _v5(['entry', normalizedTerm, source, target]);
  static String sense(String entryId, String senseKey) =>
      _v5(['sense', entryId, senseKey]);
  static String card(String senseId) => _v5(['card', senseId]);

  /// Rewrites legacy random IDs (pre-sync databases, older backups) to their
  /// deterministic form and repoints every reference. Must run inside a
  /// transaction; foreign keys are checked when it commits.
  static Future<void> normalize(DatabaseExecutor tx) async {
    await tx.execute('PRAGMA defer_foreign_keys = ON');
    Future<void> move(
      String table,
      String oldId,
      String newId,
      List<(String, String)> refs,
    ) async {
      if (oldId == newId) return;
      await tx.update(table, {'id': newId}, where: 'id=?', whereArgs: [oldId]);
      for (final (refTable, column) in refs) {
        await tx.update(
          refTable,
          {column: newId},
          where: '$column=?',
          whereArgs: [oldId],
        );
      }
    }

    for (final r in await tx.query('decks', columns: ['id', 'deck_key'])) {
      await move('decks', r['id'] as String, deck(r['deck_key'] as String), [
        ('deck_entries', 'deck_id'),
      ]);
    }
    for (final r in await tx.query('entries')) {
      await move(
        'entries',
        r['id'] as String,
        entry(
          r['normalized_term'] as String,
          r['source_language'] as String,
          r['target_language'] as String,
        ),
        [('senses', 'entry_id'), ('deck_entries', 'entry_id')],
      );
    }
    for (final r in await tx.query(
      'senses',
      columns: ['id', 'entry_id', 'sense_key'],
    )) {
      await move(
        'senses',
        r['id'] as String,
        sense(r['entry_id'] as String, r['sense_key'] as String),
        [('cards', 'sense_id'), ('sense_origins', 'sense_id')],
      );
    }
    for (final r in await tx.query('cards', columns: ['id', 'sense_id'])) {
      await move('cards', r['id'] as String, card(r['sense_id'] as String), [
        ('review_events', 'card_id'),
      ]);
    }
  }
}
