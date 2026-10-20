import 'dart:convert';

import 'models.dart';

const importFields = [
  'term',
  'meaning',
  'deck_key',
  'deck_name',
  'sense_key',
  'source_language',
  'target_language',
  'part_of_speech',
  'pronunciation',
  'note',
];
const importLabels = {
  'term': 'Từ',
  'meaning': 'Nghĩa',
  'deck_key': 'Mã nhóm',
  'deck_name': 'Tên nhóm',
  'sense_key': 'Mã nghĩa',
  'source_language': 'Ngôn ngữ nguồn',
  'target_language': 'Ngôn ngữ đích',
  'part_of_speech': 'Từ loại',
  'pronunciation': 'Phiên âm',
  'note': 'Ghi chú',
};
const importMaxBytes = 20 * 1024 * 1024;
const importMaxRows = 10000;

class ImportTable {
  const ImportTable(
    this.name,
    this.rows,
    this.columns, {
    this.canonical = false,
  });
  final String name;
  final List<Map<String, Object?>> rows;
  final List<String> columns;
  final bool canonical;
}

// JSON pointers preserve literal keys containing dots, slashes and tildes.
String _escape(String s) => s.replaceAll('~', '~0').replaceAll('/', '~1');
String columnLabel(String path) => path
    .split('/')
    .skip(1)
    .map((s) => s.replaceAll('~1', '/').replaceAll('~0', '~'))
    .join(' › ');
Map<String, Object?> _flatten(Map map, [String prefix = '', int depth = 0]) {
  if (depth > 8) throw const FormatException('JSON lồng quá sâu.');
  final result = <String, Object?>{};
  for (final entry in map.entries) {
    final path = '$prefix/${_escape(entry.key as String)}';
    if (entry.value is Map && (entry.value as Map).isNotEmpty) {
      result.addAll(_flatten(entry.value as Map, path, depth + 1));
    } else {
      result[path] = entry.value;
    }
    if (result.length > 64) {
      throw const FormatException('Tối đa 64 cột đầu vào.');
    }
  }
  return result;
}

/// Runs in a worker isolate. Throws FormatException, never logs file contents.
List<ImportTable> parseImport(Map<String, Object> input) {
  final bytes = input['bytes'] as List<int>;
  if (bytes.length > importMaxBytes) {
    throw const FormatException('File vượt 20 MiB.');
  }
  final text = utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), '');
  if (text.contains('\u0000')) {
    throw const FormatException('File có ký tự NUL không hợp lệ.');
  }
  if (input['extension'] == 'csv') {
    return [_csv(text, input['delimiter'] as String? ?? ',')];
  }
  _checkJsonKeys(text);
  final root = jsonDecode(text);
  final tables = <ImportTable>[];
  final canonical = root is Map && root.containsKey('schema_version');
  if (canonical &&
      (root['schema_version'] != '1.0' ||
          root.length != 2 ||
          root['items'] is! List)) {
    throw const FormatException(
      'Envelope JSON cần schema_version 1.0 và items; không có trường khác.',
    );
  }
  void find(Object? node, String path, int depth) {
    if (depth > 8) throw const FormatException('JSON lồng quá sâu.');
    if (node is List) {
      if (node.length > importMaxRows) {
        throw const FormatException(
          'Danh sách vượt 10.000 dòng. Hãy chia file.',
        );
      }
      final columns = <String>{};
      final rows = <Map<String, Object?>>[];
      for (final row in node) {
        final flat = row is Map
            ? _flatten(row)
            : <String, Object?>{'!error': 'Dòng phải là object JSON.'};
        columns.addAll(flat.keys.where((k) => k != '!error'));
        if (columns.length > 64) {
          throw const FormatException('Tối đa 64 cột đầu vào.');
        }
        if (canonical &&
            row is Map &&
            row.keys.any((k) => !importFields.contains(k))) {
          flat['!error'] = 'Schema v1 có trường lạ; hãy dùng đúng template hoặc bỏ envelope schema_version để ánh xạ linh hoạt.';
        }
        rows.add(flat);
      }
      tables.add(
        ImportTable(
          path.isEmpty ? '/' : path,
          rows,
          columns.toList(),
          canonical: canonical,
        ),
      );
    } else if (node is Map) {
      for (final e in node.entries) {
        find(e.value, '$path/${_escape(e.key as String)}', depth + 1);
      }
    }
  }

  if (canonical) {
    find(root['items'], '/items', 0);
  } else {
    find(root, '', 0);
  }
  if (tables.isEmpty) {
    throw const FormatException(
      'Không tìm thấy danh sách JSON. Dùng array hoặc object chứa items/vocabulary.',
    );
  }
  if (tables.length > 32) {
    throw const FormatException('Có quá nhiều danh sách trong JSON.');
  }
  return tables;
}

void _checkJsonKeys(String text) {
  // jsonDecode alone accepts duplicate keys. Tokenize strings before decoding.
  final frames = <({bool object, Set<String> keys, bool expectingKey})>[];
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      final start = i++;
      while (i < text.length) {
        if (text[i] == '\\') {
          i += 2;
          continue;
        }
        if (text[i] == '"') break;
        i++;
      }
      if (i >= text.length) {
        throw const FormatException('Chuỗi JSON chưa đóng.');
      }
      if (frames.isNotEmpty && frames.last.object && frames.last.expectingKey) {
        final key = jsonDecode(text.substring(start, i + 1)) as String;
        if (!frames.last.keys.add(key)) {
          throw const FormatException('JSON có key trùng trong cùng object.');
        }
        final f = frames.removeLast();
        frames.add((object: true, keys: f.keys, expectingKey: false));
      }
    } else if (c == '{' || c == '[') {
      frames.add((object: c == '{', keys: <String>{}, expectingKey: c == '{'));
      if (frames.length > 32) throw const FormatException('JSON lồng quá sâu.');
    } else if (c == '}' || c == ']') {
      if (frames.isEmpty) {
        throw const FormatException('JSON đóng ngoặc không hợp lệ.');
      }
      frames.removeLast();
    } else if (c == ',' && frames.isNotEmpty && frames.last.object) {
      final f = frames.removeLast();
      frames.add((object: true, keys: f.keys, expectingKey: true));
    }
  }
}

ImportTable _csv(String text, String delimiter) {
  if (![',', ';', '\t'].contains(delimiter)) {
    throw const FormatException('Delimiter không hỗ trợ.');
  }
  final records = <List<String>>[];
  var cells = <String>[], cell = StringBuffer();
  var quoted = false, closed = false, started = false;
  void finishCell() {
    cells.add(cell.toString());
    cell = StringBuffer();
    closed = false;
    started = false;
  }

  void finishRow() {
    finishCell();
    if (cells.any((v) => v.trim().isNotEmpty)) records.add(cells);
    cells = [];
    if (records.length > importMaxRows + 1) {
      throw const FormatException('CSV vượt 10.000 dòng.');
    }
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        cell.write(c);
      }
    } else if (c == delimiter) {
      finishCell();
    } else if (c == '\r' || c == '\n') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      finishRow();
    } else if (c == '"' && !started && !closed) {
      quoted = true;
      started = true;
    } else {
      if (c == '"' || closed) {
        throw const FormatException(
          'CSV quote sai. Giá trị chứa dấu phân cách/xuống dòng cần bọc trong dấu nháy kép.',
        );
      }
      started = true;
      cell.write(c);
    }
    if (cell.length > 20000 || cells.length > 64) {
      throw const FormatException('CSV vượt giới hạn độ dài ô hoặc 64 cột.');
    }
  }
  if (quoted) throw const FormatException('CSV có quote chưa đóng.');
  if (started || closed || cell.isNotEmpty || cells.isNotEmpty) finishRow();
  if (records.isEmpty) throw const FormatException('CSV trống.');
  final headers = records.removeAt(0).map((s) => s.trim()).toList();
  if (headers.length > 64 ||
      headers.any((s) => s.isEmpty) ||
      headers.toSet().length != headers.length) {
    throw const FormatException('Header CSV trống, trùng hoặc quá 64 cột.');
  }
  final columns = headers.map((s) => '/${_escape(s)}').toList();
  return ImportTable(
    'CSV',
    records
        .map(
          (r) => <String, Object?>{
            for (var i = 0; i < columns.length; i++)
              columns[i]: i < r.length ? r[i] : null,
            if (r.length != columns.length)
              '!error':
                  'Số ô không khớp header (${r.length}/${columns.length}).',
          },
        )
        .toList(),
    columns,
  );
}

Map<String, String?> suggestMapping(List<String> columns) {
  const aliases = {
    'term': ['term', 'word', 'vocabulary', 'từ'],
    'meaning': ['meaning', 'definition', 'translation', 'nghĩa'],
    'deck_key': ['deck_key', 'group_key'],
    'deck_name': ['deck_name', 'group', 'deck', 'nhóm'],
    'sense_key': ['sense_key'],
    'source_language': ['source_language'],
    'target_language': ['target_language'],
    'part_of_speech': ['part_of_speech', 'pos'],
    'pronunciation': ['pronunciation', 'ipa'],
    'note': ['note', 'notes'],
  };
  return {
    for (final field in importFields)
      field: columns
          .where((c) => aliases[field]!.contains(columnLabel(c).toLowerCase()))
          .firstOrNull,
  };
}

class ImportRow {
  const ImportRow(
    this.number,
    this.values,
    this.errors, {
    this.original = const {},
  });
  final int number;
  final Map<String, Object?> values, original;
  final List<String> errors;
  String text(String field) => values[field] as String? ?? '';
  String display(String field) =>
      values[field]?.toString() ?? original[field]?.toString() ?? '';
  String get entryKey => jsonEncode([
    text('term'),
    text('source_language'),
    text('target_language'),
  ]);
  String get senseKey => jsonEncode([entryKey, text('sense_key')]);
  String get membershipKey => jsonEncode([entryKey, text('deck_key')]);
  String get signature => jsonEncode([
    for (final f in ['meaning', 'part_of_speech', 'pronunciation', 'note'])
      values[f],
  ]);
}

ImportRow validateImportRow(
  int number,
  Map<String, Object?> input, {
  String? sourceError,
}) {
  final errors = <String>[?sourceError];
  final values = <String, Object?>{};
  for (final field in importFields) {
    final value = input[field];
    if (value != null && value is! String) {
      errors.add('${importLabels[field]} phải là chuỗi, không tự đổi kiểu.');
      values[field] = null;
      continue;
    }
    final normalized = value == null
        ? ''
        : (field == 'term' || field == 'deck_name'
              ? normalizeTerm(value as String)
              : normalizeMeaning(value as String));
    values[field] = normalized.isEmpty ? null : normalized;
  }
  String text(String field) => values[field] as String? ?? '';
  for (final field in [
    'term',
    'deck_key',
    'deck_name',
    'sense_key',
    'source_language',
    'target_language',
  ]) {
    if (text(field).isEmpty) errors.add('Thiếu ${importLabels[field]}.');
  }
  for (final field in ['deck_key', 'sense_key']) {
    if (text(field).isNotEmpty &&
        !RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(text(field))) {
      errors.add(
        '${importLabels[field]} cần slug chữ thường, số, - hoặc _ (1–64).',
      );
    }
  }
  const limits = {
    'term': 200,
    'meaning': 1000,
    'deck_name': 120,
    'pronunciation': 200,
    'note': 1000,
  };
  for (final e in limits.entries) {
    if (text(e.key).length > e.value) {
      errors.add('${importLabels[e.key]} vượt ${e.value} ký tự.');
    }
  }
  if (text('source_language').isNotEmpty && text('source_language') != 'en' ||
      text('target_language').isNotEmpty && text('target_language') != 'vi') {
    errors.add('Bản này chỉ nhập Anh (en) → Việt (vi).');
  }
  if (values['part_of_speech'] != null &&
      ![
        'noun',
        'verb',
        'adjective',
        'adverb',
        'pronoun',
        'preposition',
        'conjunction',
        'interjection',
        'determiner',
        'phrase',
        'other',
      ].contains(values['part_of_speech'])) {
    errors.add('Từ loại không hợp lệ.');
  }
  return ImportRow(number, values, errors, original: Map.of(input));
}

String exportImportCsv(
  List<ImportRow> rows, {
  bool errors = false,
  Map<int, String> messages = const {},
}) {
  final fields = [
    if (errors) ...['row_number', 'validation', 'raw_values'],
    ...importFields,
  ];
  String cell(Object? raw) {
    var text = raw?.toString() ?? '';
    if (RegExp(r'^[\s\uFEFF]*[=+@-]').hasMatch(text) ||
        text.startsWith('\t') ||
        text.startsWith('\r')) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  return '\uFEFF${[fields.map(cell).join(','), ...rows.map((r) => fields.map((f) => cell(f == 'row_number'
      ? r.number
      : f == 'raw_values'
      ? jsonEncode(r.original)
      : f == 'validation'
      ? messages[r.number]
      : r.values[f])).join(','))].join('\r\n')}\r\n';
}
