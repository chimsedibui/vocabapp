import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../domain/import_data.dart';
import '../domain/models.dart';
import 'library_repository.dart';

class ImportSnapshot {
  const ImportSnapshot(this.decks, this.entries, this.senses, this.memberships);
  final Map<String, Map<String, Object?>> decks, entries, senses;
  final Set<String> memberships;
}

class ImportCheck {
  const ImportCheck(this.row, this.status, this.issues, this.warnings);
  final ImportRow row;
  final String status;
  final List<String> issues, warnings;
  bool get valid => issues.isEmpty;
  String get message => [...issues, ...warnings].join(' ');
}

List<ImportCheck> planImport(
  List<ImportRow> rows,
  Set<int> selected,
  ImportSnapshot db,
) {
  final senseValues = <String, Set<String>>{},
      deckNames = <String, Set<String>>{};
  for (final row in rows.where(
    (r) => selected.contains(r.number) && r.errors.isEmpty,
  )) {
    senseValues.putIfAbsent(row.senseKey, () => {}).add(row.signature);
    deckNames
        .putIfAbsent(row.text('deck_key'), () => {})
        .add(row.text('deck_name'));
  }
  final seen = <String, int>{};
  final lowerTerms = db.entries.values
      .map((r) => (r['normalized_term'] as String).toLowerCase())
      .toSet();
  return rows.map((row) {
    final issues = [...row.errors], warnings = <String>[];
    var status = 'Mới';
    if (row.errors.isEmpty) {
      if (selected.contains(row.number) &&
          (senseValues[row.senseKey]?.length ?? 0) > 1) {
        issues.add(
          'Xung đột trong file: cùng từ/mã nghĩa có nội dung khác. Bỏ chọn một dòng hoặc sửa mã nghĩa.',
        );
      }
      if (selected.contains(row.number) &&
          (deckNames[row.text('deck_key')]?.length ?? 0) > 1) {
        issues.add('Xung đột tên nhóm trong các dòng đang chọn.');
      }
      final deck = db.decks[row.text('deck_key')];
      if (deck != null &&
          (deck['archived'] == 1 || deck['name'] != row.text('deck_name'))) {
        issues.add(
          'Mã nhóm đã có tên khác hoặc đã lưu trữ. Chọn nhóm đích hoặc sửa mã/tên nhóm.',
        );
      }
      final sense = db.senses[row.senseKey];
      if (sense != null) {
        for (final field in [
          'meaning',
          'part_of_speech',
          'pronunciation',
          'note',
        ]) {
          final incoming = row.values[field];
          if (incoming != null && incoming != sense[field]) {
            issues.add(
              '${importLabels[field]} khác dữ liệu đang có. Không ghi đè; sửa mã nghĩa để thêm nghĩa khác hoặc bỏ chọn.',
            );
          }
        }
        status = db.memberships.contains(row.membershipKey)
            ? 'Đã có'
            : 'Thêm vào nhóm';
        if (sense['status'] == 'draft' &&
            (sense['meaning'] as String).isNotEmpty) {
          warnings.add(
            'Nghĩa hiện có đang là nháp; có thể duyệt khi xác nhận.',
          );
        }
      }
      if (!db.entries.containsKey(row.entryKey) &&
          lowerTerms.contains(row.text('term').toLowerCase())) {
        warnings.add(
          'Có từ chỉ khác hoa/thường. App giữ riêng; không tự hợp nhất.',
        );
      }
      if (row.values['meaning'] == null) {
        warnings.add(
          sense == null
              ? 'Thiếu nghĩa: lưu nháp, không tạo thẻ học.'
              : 'Thiếu nghĩa trong file: giữ nguyên nghĩa hiện có.',
        );
      }
      final signature = jsonEncode([
        row.senseKey,
        row.membershipKey,
        row.signature,
      ]);
      if (selected.contains(row.number) && issues.isEmpty) {
        final previous = seen[signature];
        if (previous != null) {
          status = 'Trùng trong file';
          warnings.add('Giống dòng $previous; chỉ xử lý một lần.');
        } else {
          seen[signature] = row.number;
        }
      }
    }
    if (issues.isNotEmpty) status = row.errors.isEmpty ? 'Xung đột' : 'Lỗi';
    return ImportCheck(row, status, issues, warnings);
  }).toList();
}

class ImportResult {
  const ImportResult(
    this.senses,
    this.memberships,
    this.approved,
    this.skipped,
  );
  final int senses, memberships, approved, skipped;
}

class ImportRepository {
  ImportRepository(this.library);
  final LibraryRepository library;
  final _uuid = const Uuid();
  Future<ImportSnapshot> snapshot() => library.db.transaction(readSnapshot);
  static Future<ImportSnapshot> readSnapshot(DatabaseExecutor tx) async {
    final decks = {
      for (final r in await tx.query('decks')) r['deck_key'] as String: r,
    };
    final entries = <String, Map<String, Object?>>{};
    final entryKeys = <String, String>{};
    for (final r in await tx.query('entries')) {
      final key = jsonEncode([
        r['normalized_term'],
        r['source_language'],
        r['target_language'],
      ]);
      entries[key] = r;
      entryKeys[r['id'] as String] = key;
    }
    final senses = {
      for (final r in await tx.query('senses'))
        jsonEncode([entryKeys[r['entry_id']], r['sense_key']]): r,
    };
    final deckKeys = {for (final r in decks.values) r['id']: r['deck_key']};
    final memberships = {
      for (final r in await tx.query('deck_entries'))
        jsonEncode([entryKeys[r['entry_id']], deckKeys[r['deck_id']]]),
    };
    return ImportSnapshot(decks, entries, senses, memberships);
  }

  Future<ImportResult> commit(
    List<ImportRow> selected, {
    required bool approve,
    required String fileName,
    required String fileHash,
  }) => library.db.transaction((tx) async {
    if (selected.isEmpty ||
        selected.length > importMaxRows ||
        selected.map((r) => r.number).toSet().length != selected.length) {
      throw const UserFacingException(
        'Chọn từ 1 đến 10.000 dòng, số dòng không trùng.',
      );
    }
    // Never trust cached UI validation or writable DTOs at the write boundary.
    final checked = selected
        .map(
          (r) => validateImportRow(
            r.number,
            r.values,
            sourceError: r.errors.isEmpty ? null : r.errors.join(' '),
          ),
        )
        .toList();
    final current = await readSnapshot(tx);
    final plan = planImport(
      checked,
      checked.map((r) => r.number).toSet(),
      current,
    );
    if (plan.any((r) => !r.valid)) {
      throw const UserFacingException(
        'Dữ liệu hoặc thư viện đã thay đổi. Còn dòng lỗi/xung đột đang chọn; hãy kiểm tra lại trước khi nhập.',
      );
    }
    var senses = 0, memberships = 0, approved = 0, skipped = 0;
    for (final check in plan) {
      if (check.status == 'Trùng trong file') {
        skipped++;
        continue;
      }
      final row = check.row;
      var deck = current.decks[row.text('deck_key')];
      if (deck == null) {
        deck = {
          'id': _uuid.v4(),
          'deck_key': row.text('deck_key'),
          'name': row.text('deck_name'),
          'archived': 0,
        };
        await tx.insert('decks', deck);
        current.decks[row.text('deck_key')] = deck;
      }
      var entry = current.entries[row.entryKey];
      if (entry == null) {
        entry = {
          'id': _uuid.v4(),
          'term': row.text('term'),
          'normalized_term': row.text('term'),
          'source_language': row.text('source_language'),
          'target_language': row.text('target_language'),
          'created_at': library.clock().toUtc().millisecondsSinceEpoch,
        };
        await tx.insert('entries', entry);
        current.entries[row.entryKey] = entry;
      }
      var sense = current.senses[row.senseKey];
      final shouldApprove = approve && row.text('meaning').isNotEmpty;
      var changed = false;
      if (sense == null) {
        sense = {
          'id': _uuid.v4(),
          'entry_id': entry['id'],
          'sense_key': row.text('sense_key'),
          'meaning': row.text('meaning'),
          'search_text': '${row.text('term')} ${row.text('meaning')}'
              .toLowerCase(),
          'status': shouldApprove ? 'approved' : 'draft',
          for (final f in ['part_of_speech', 'pronunciation', 'note'])
            f: row.values[f],
        };
        await tx.insert('senses', sense);
        current.senses[row.senseKey] = sense;
        senses++;
        changed = true;
        if (shouldApprove) {
          await tx.insert('cards', {'id': _uuid.v4(), 'sense_id': sense['id']});
          approved++;
        }
      } else if (shouldApprove &&
          sense['status'] == 'draft' &&
          (sense['meaning'] as String).isNotEmpty) {
        await tx.update(
          'senses',
          {'status': 'approved'},
          where: 'id=?',
          whereArgs: [sense['id']],
        );
        await tx.insert('cards', {'id': _uuid.v4(), 'sense_id': sense['id']});
        sense = {...sense, 'status': 'approved'};
        current.senses[row.senseKey] = sense;
        approved++;
        changed = true;
      }
      if (current.memberships.add(row.membershipKey)) {
        await tx.insert('deck_entries', {
          'deck_id': deck['id'],
          'entry_id': entry['id'],
        });
        memberships++;
        changed = true;
      }
      if (!changed) skipped++;
    }
    await tx.insert('import_batches', {
      'id': _uuid.v4(),
      'source_name': fileName.length > 255
          ? fileName.substring(0, 255)
          : fileName,
      'source_hash': fileHash,
      'created_at': library.clock().toUtc().millisecondsSinceEpoch,
      'selected_rows': selected.length,
      'new_senses': senses,
      'memberships': memberships,
      'approved': approved,
      'skipped': skipped,
    });
    return ImportResult(senses, memberships, approved, skipped);
  });
}
