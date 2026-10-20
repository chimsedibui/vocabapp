import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/passage.dart';
import '../services/ai_configuration.dart';
import '../services/passage_service.dart';
import 'ids.dart';
import 'library_repository.dart';

class ReviewedItem {
  const ReviewedItem(this.item, {this.existingSenseId});
  final PassageItem item;
  final String? existingSenseId;
}

class PassageRepository {
  PassageRepository(this.library);
  final LibraryRepository library;
  Database get db => library.db;
  final _uuid = const Uuid();
  Future<List<Map<String, Object?>>> history() => db.query(
    'passage_jobs',
    columns: ['id', 'created_at', 'status', 'min_level', 'provider', 'model'],
    orderBy: 'created_at DESC',
    limit: 30,
  );
  Future<Map<String, Object?>> job(String id) async =>
      (await db.query('passage_jobs', where: 'id=?', whereArgs: [id])).single;
  Future<void> delete(String id) => db.transaction((tx) async {
    await tx.delete('passage_jobs', where: 'id=?', whereArgs: [id]);
  });
  Future<String?> cached(String key) async {
    final rows = await db.query(
      'passage_jobs',
      columns: ['id'],
      where: "cache_key=? AND status='complete' AND created_at>=?",
      whereArgs: [
        key,
        library
            .clock()
            .toUtc()
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch,
      ],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.firstOrNull?['id'] as String?;
  }

  Future<String> create(
    PassageRequest request,
    AiPreferences preferences,
  ) async {
    final id = _uuid.v4();
    await db.insert('passage_jobs', {
      'id': id,
      'source_text': request.text,
      'min_level': request.minLevel,
      'max_items': request.maxItems,
      'cache_key': request.cacheKey(preferences.identity),
      'created_at': library.clock().toUtc().millisecondsSinceEpoch,
      'status': 'pending',
    });
    return id;
  }

  Future<void> attempt(String id, Map<String, Object?> attempt) async {
    final row = await job(id);
    final attempts = jsonDecode(row['attempts_json'] as String) as List;
    // Only usage/accounting fields from the service; no response/passage/key.
    attempts.add(attempt);
    await db.update(
      'passage_jobs',
      {'attempts_json': jsonEncode(attempts)},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> complete(String id, ExtractionResponse response) async {
    await db.update(
      'passage_jobs',
      {
        'status': 'complete',
        'result_json': response.result.json,
        'provider': response.configuration.provider.name,
        'model': response.configuration.model,
        'removed': response.result.removed,
        'at_limit': response.result.atLimit ? 1 : 0,
        'error_text': null,
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> fail(String id, UserFacingException error) async {
    await db.update(
      'passage_jobs',
      {
        'status': error is PassageCancelled ? 'cancelled' : 'error',
        'error_text': error.message,
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<List<Vocabulary>> matches(String term) async {
    final rows = await db.rawQuery(
      '''SELECT s.*, e.term, e.id AS entry
      FROM senses s JOIN entries e ON s.entry_id=e.id
      WHERE e.normalized_term=? AND e.source_language='en' AND e.target_language='vi' ''',
      [normalizeTerm(term)],
    );
    return rows
        .map(
          (r) => Vocabulary(
            entryId: r['entry'] as String,
            senseId: r['id'] as String,
            term: r['term'] as String,
            meaning: r['meaning'] as String,
            senseKey: r['sense_key'] as String,
            status: r['status'] as String,
            groups: '',
            suspended: false,
          ),
        )
        .toList();
  }

  /// All selected rows commit together. No existing text, card or review is overwritten.
  Future<int> approve(
    String jobId,
    String deckId,
    List<ReviewedItem> selected,
  ) => db.transaction((tx) async {
    final jobs = await tx.query(
      'passage_jobs',
      where: "id=? AND status='complete'",
      whereArgs: [jobId],
    );
    if (jobs.isEmpty || selected.isEmpty || selected.length > 100) {
      throw const UserFacingException(
        'Chọn kết quả của passage đã trích thành công.',
      );
    }
    if ((await tx.query(
      'decks',
      where: 'id=? AND archived=0',
      whereArgs: [deckId],
    )).isEmpty) {
      throw const UserFacingException('Nhóm không còn khả dụng.');
    }
    final job = jobs.single;
    final request = PassageRequest(
      job['source_text'] as String,
      minLevel: job['min_level'] as String,
      maxItems: job['max_items'] as int,
    );
    final original = validatePassageResult(
      job['result_json'] as String,
      request,
    ).items;
    var added = 0;
    for (final selection in selected) {
      final valid = validatePassageResult(
        jsonEncode({
          'items': [selection.item.toJson()],
        }),
        request,
      );
      if (valid.items.length != 1) {
        throw const UserFacingException(
          'Từ sửa phải có trong passage và đạt mức đã chọn.',
        );
      }
      final item = valid.items.single;
      final entries = await tx.query(
        'entries',
        where: "normalized_term=? AND source_language='en' AND target_language='vi'",
        whereArgs: [item.term],
      );
      final entryId = entries.isEmpty
          ? Ids.entry(item.term, 'en', 'vi')
          : entries.single['id'] as String;
      if (entries.isEmpty) {
        await tx.insert('entries', {
          'id': entryId,
          'term': item.term,
          'normalized_term': item.term,
          'created_at': library.clock().toUtc().millisecondsSinceEpoch,
        });
      }
      final senses = await tx.query(
        'senses',
        where: 'entry_id=?',
        whereArgs: [entryId],
      );
      Map<String, Object?>? existing;
      if (selection.existingSenseId != null) {
        existing = senses
            .where((r) => r['id'] == selection.existingSenseId)
            .firstOrNull;
        if (existing == null || existing['status'] != 'approved') {
          throw const UserFacingException('Nghĩa đã chọn không còn khả dụng.');
        }
      } else {
        existing = senses
            .where(
              (r) => normalizeMeaning(r['meaning'] as String) == item.meaning,
            )
            .firstOrNull;
      }
      final senseKey = 'ai-${_uuid.v4()}';
      final senseId =
          existing?['id'] as String? ?? Ids.sense(entryId, senseKey);
      if (existing == null) {
        await tx.insert('senses', {
          'id': senseId,
          'entry_id': entryId,
          'sense_key': senseKey,
          'meaning': item.meaning,
          'search_text': '${item.term} ${item.meaning}'.toLowerCase(),
          'status': 'approved',
        });
        added++;
      } else if (existing['status'] == 'draft') {
        await tx.update(
          'senses',
          {'status': 'approved'},
          where: 'id=?',
          whereArgs: [senseId],
        );
        added++;
      }
      if (existing == null || existing['status'] == 'draft') {
        await tx.insert('cards', {
          'id': Ids.card(senseId),
          'sense_id': senseId,
        });
      }
      await tx.insert('deck_entries', {
        'deck_id': deckId,
        'entry_id': entryId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      // A user-selected older meaning may differ from the model's meaning; do not mislabel it.
      if (selection.existingSenseId == null ||
          existing?['meaning'] == item.meaning) {
        await tx.insert('sense_origins', {
          'id': _uuid.v4(),
          'sense_id': senseId,
          'job_id': jobId,
          'estimated_level': item.level,
          'level_source':
              original.any((p) => p.term == item.term && p.level == item.level)
              ? 'llm'
              : 'user',
          'provider': job['provider'],
          'model': job['model'],
          'created_at': library.clock().toUtc().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    return added;
  });
}
