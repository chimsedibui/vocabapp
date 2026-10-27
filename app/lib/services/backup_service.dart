import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../domain/models.dart';
import '../domain/passage.dart';
import '../data/ids.dart';

class BackupSummary {
  const BackupSummary(
    this.entries,
    this.senses,
    this.reviews, [
    this.passages = 0,
  ]);
  final int entries, senses, reviews, passages;
}

/// Versioned logical snapshot. All reads/writes share SQLite transactions.
class BackupService {
  BackupService(this.db);
  final Database db;
  static const maxBytes = 20 * 1024 * 1024;
  static const tables = [
    'settings',
    'decks',
    'entries',
    'senses',
    'deck_entries',
    'cards',
    'review_events',
    'passage_jobs',
    'sense_origins',
    'import_batches',
  ];

  Future<Uint8List> export() => db.transaction(_capture);

  Future<Uint8List> _capture(DatabaseExecutor tx) async {
    final rows = {
      for (final table in tables)
        table: await tx.query(
          table,
          orderBy: table == 'deck_entries' ? 'deck_id,entry_id' : 'id',
        ),
    };
    final payload = jsonEncode(rows);
    final encoded = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'vocabapp-backup',
          'version': 3,
          'db_version': 3,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'sha256': sha256.convert(utf8.encode(payload)).toString(),
          'data': rows,
        }),
      ),
    );
    if (encoded.length > maxBytes) {
      throw const UserFacingException(
        'Thư viện vượt giới hạn sao lưu 20 MiB của phiên bản này.',
      );
    }
    return encoded;
  }

  Map<String, dynamic> _decode(Uint8List bytes) {
    try {
      if (bytes.length > maxBytes) throw const FormatException();
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (root['format'] != 'vocabapp-backup' ||
          !((root['version'] == 1 && root['db_version'] == 1) ||
              (root['version'] == 2 && root['db_version'] == 2) ||
              (root['version'] == 3 && root['db_version'] == 3))) {
        throw const FormatException();
      }
      final data = root['data'] as Map<String, dynamic>;
      final oldTables = tables.take(
        root['version'] == 1
            ? 7
            : root['version'] == 2
            ? 9
            : 10,
      );
      if (data.length != oldTables.length ||
          !oldTables.every(data.containsKey) ||
          sha256.convert(utf8.encode(jsonEncode(data))).toString() !=
              root['sha256']) {
        throw const FormatException();
      }
      if (root['version'] == 1) {
        data['passage_jobs'] = <dynamic>[];
        data['sense_origins'] = <dynamic>[];
      }
      if ((root['version'] as int) < 3) {
        data['import_batches'] = <dynamic>[];
        for (final row in data['senses'] as List) {
          for (final field in ['part_of_speech', 'pronunciation', 'note']) {
            if ((row as Map).containsKey(field)) throw const FormatException();
            row[field] = null;
          }
        }
      }
      var total = 0;
      for (final table in tables) {
        final rows = data[table] as List;
        total += rows.length;
        if (total > 200000) throw const FormatException();
        for (final row in rows) {
          if (row is! Map<String, dynamic>) throw const FormatException();
        }
      }
      if ((data['settings'] as List).length != 1) throw const FormatException();
      return data;
    } catch (_) {
      throw const UserFacingException(
        'Bản sao lưu không hợp lệ, bị thay đổi hoặc có phiên bản chưa hỗ trợ.',
      );
    }
  }

  BackupSummary inspect(Uint8List bytes) {
    final data = _decode(bytes);
    return BackupSummary(
      (data['entries'] as List).length,
      (data['senses'] as List).length,
      (data['review_events'] as List).length,
      (data['passage_jobs'] as List).length,
    );
  }

  Future<void> restore(
    Uint8List bytes, {
    required Future<void> Function(Uint8List) saveRecovery,
  }) async {
    final data = _decode(bytes);
    // Validate every field before creating a recovery snapshot or changing data.
    for (final table in tables) {
      final schema = await db.rawQuery('PRAGMA table_info($table)');
      for (final raw in data[table] as List) {
        final row = raw as Map<String, dynamic>;
        if (row.length != schema.length ||
            schema.any((c) => !row.containsKey(c['name']))) {
          throw const UserFacingException(
            'Cấu trúc bản sao lưu không khớp phiên bản ứng dụng.',
          );
        }
        for (final col in schema) {
          final value = row[col['name']];
          final required = col['notnull'] == 1 || col['pk'] == 1;
          if ((value == null && required) ||
              (value != null &&
                  col['type'] == 'TEXT' &&
                  (value is! String ||
                      value.length >
                          (table == 'passage_jobs'
                              ? (col['name'] == 'source_text'
                                    ? maxPassageChars
                                    : 100000)
                              : 4096))) ||
              (value != null && col['type'] == 'INTEGER' && value is! int)) {
            throw const UserFacingException(
              'Bản sao lưu có trường dữ liệu không hợp lệ.',
            );
          }
        }
      }
    }
    final config = (data['settings'] as List).single as Map<String, dynamic>;
    if (config['id'] != 1 || config['timezone'] != 'Asia/Ho_Chi_Minh') {
      throw const UserFacingException(
        'Cấu hình ngày học trong bản sao lưu chưa được hỗ trợ.',
      );
    }
    try {
      await db.transaction((tx) async {
        await saveRecovery(
          await _capture(tx),
        ); // Blocks concurrent writes until the restore commits.
        final deviceId = (await tx.query('settings')).single['device_id'];
        for (final table in tables.reversed) {
          await tx.delete(table);
        }
        for (final table in tables) {
          for (final raw in data[table] as List) {
            final row = Map<String, Object?>.from(raw as Map);
            if (table == 'settings') row['device_id'] = deviceId;
            await tx.insert(table, row);
          }
        }
        // Older backups carry random IDs; sync relies on deterministic ones.
        await Ids.normalize(tx);
        final invalidCards = await tx.rawQuery("""
          SELECT c.id FROM cards c JOIN senses s ON s.id=c.sense_id
          WHERE s.status!='approved' OR c.interval_days NOT BETWEEN 1 AND 365
            OR c.lapses<0 OR c.revision<0 OR c.suspended NOT IN (0,1)
            OR (c.state='new' AND c.due_at IS NOT NULL)
            OR (c.state!='new' AND c.due_at IS NULL)
            OR c.scheduler_version!=1
        """);
        final missingCards = await tx.rawQuery(
          "SELECT s.id FROM senses s LEFT JOIN cards c ON c.sense_id=s.id WHERE s.status='approved' AND c.id IS NULL",
        );
        if (invalidCards.isNotEmpty || missingCards.isNotEmpty) {
          throw const FormatException('Invalid card state');
        }
        if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
          throw const FormatException('Invalid foreign keys');
        }
      });
    } catch (_) {
      throw const UserFacingException(
        'Không khôi phục được bản sao lưu. Thư viện hiện tại vẫn được giữ nguyên.',
      );
    }
  }
}
