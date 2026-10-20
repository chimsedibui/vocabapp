import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../data/import_repository.dart';
import '../data/library_repository.dart';
import '../domain/import_data.dart';
import 'editors.dart';

List<ImportRow> _prepareRows(Map<String, Object?> args) {
  final table = args['table'] as ImportTable;
  final mapping = args['mapping'] as Map<String, String?>;
  final defaults = args['defaults'] as Map<String, Object?>;
  final edits = args['edits'] as Map<int, Map<String, Object?>>;
  return [
    for (var i = 0; i < table.rows.length; i++)
      validateImportRow(
        i + 1,
        edits[i + 1] ??
            {
              for (final field in importFields)
                field: mapping[field] == null
                    ? defaults[field]
                    : table.rows[i][mapping[field]],
            },
        sourceError: edits.containsKey(i + 1)
            ? null
            : table.rows[i]['!error'] as String?,
      ),
  ];
}

List<ImportCheck> _checkRows(Map<String, Object> args) => planImport(
  args['rows'] as List<ImportRow>,
  args['selected'] as Set<int>,
  args['snapshot'] as ImportSnapshot,
);

String _exportPreview(Map<String, Object> args) => exportImportCsv(
  args['rows'] as List<ImportRow>,
  errors: args['report'] as bool,
  messages: args['messages'] as Map<int, String>,
);

class ImportPage extends StatefulWidget {
  const ImportPage({
    super.key,
    required this.library,
    this.initialBytes,
    this.initialName,
  });
  final LibraryRepository library;
  // Optional input also supports repeatable, network-free widget tests.
  final Uint8List? initialBytes;
  final String? initialName;
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final _repo = ImportRepository(widget.library);
  final _groupName = TextEditingController(text: 'Từ nhập từ file');
  final _newGroupKey = 'import-${const Uuid().v4().substring(0, 12)}';
  List<ImportTable> _tables = [];
  int _tableIndex = 0;
  Map<String, String?> _mapping = {};
  ImportSnapshot? _snapshot;
  List<ImportRow> _rows = [];
  List<ImportCheck> _checks = [];
  final _edits = <int, Map<String, Object?>>{};
  Set<int> _selected = {};
  bool _groupDirty = false;
  bool _busy = false,
      _saving = false,
      _approve = false,
      _onlyProblems = false,
      _fileGroups = false,
      _mappingOpen = false;
  String _name = '',
      _hash = '',
      _delimiter = ',',
      _extension = '',
      _groupKey = '';
  String? _error, _notice;
  Uint8List? _bytes;
  int _generation = 0, _tableGeneration = 0;
  @override
  void initState() {
    super.initState();
    if (widget.initialBytes != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _read(
          widget.initialBytes!,
          widget.initialName ?? 'vocabulary.json',
        ),
      );
    }
  }

  @override
  void dispose() {
    _generation++;
    _groupName.dispose();
    super.dispose();
  }

  String _friendly(Object e) => e is FormatException
      ? 'Không đọc được file: ${e.message}'
      : friendlyError(e);
  Future<void> _pick() async {
    if (_busy) return;
    if (_edits.isNotEmpty && !await _confirmDiscard()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pick = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json', 'csv'],
      );
      if (pick == null || !mounted) return;
      if ((pick.lengthSync() ?? 0) > importMaxBytes) {
        throw const FormatException('File vượt 20 MiB.');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in pick.readAsByteStream()) {
        if (!mounted) return;
        if (builder.length + chunk.length > importMaxBytes) {
          throw const FormatException('File vượt 20 MiB.');
        }
        builder.add(chunk);
      }
      await _read(builder.takeBytes(), pick.name);
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _read(Uint8List bytes, String name) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final extension = name.split('.').last.toLowerCase();
      if (!['json', 'csv'].contains(extension)) {
        throw const FormatException('Chỉ hỗ trợ .json và .csv trong bản này.');
      }
      final tables = await compute(parseImport, <String, Object>{
        'bytes': bytes,
        'extension': extension,
        'delimiter': _delimiter,
      });
      final snapshot = await _repo.snapshot();
      if (!mounted) return;
      _tables = tables;
      _tableIndex = 0;
      _snapshot = snapshot;
      _bytes = bytes;
      _name = name;
      _hash = sha256.convert(bytes).toString();
      _extension = extension;
      _groupKey =
          snapshot.decks.values
                  .where((d) => d['archived'] == 0)
                  .firstOrNull?['deck_key']
              as String? ??
          '';
      _edits.clear();
      _mapping = suggestMapping(_tables.first.columns);
      _mappingOpen = _mapping['term'] == null;
      _fileGroups =
          _mapping['deck_key'] != null && _mapping['deck_name'] != null;
      _selected = {for (var i = 1; i <= tables.first.rows.length; i++) i};
      _approve = false;
      await _rebuild();
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, Object?> get _defaults {
    final deck = _snapshot?.decks[_groupKey];
    return {
      'source_language': 'en',
      'target_language': 'vi',
      'sense_key': 'primary',
      'deck_key': deck?['deck_key'] ?? _newGroupKey,
      'deck_name': deck?['name'] ?? _groupName.text,
    };
  }

  Future<void> _rebuild() async {
    if (_tables.isEmpty || _snapshot == null) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mapping = {..._mapping};
      if (!_fileGroups) {
        mapping['deck_key'] = null;
        mapping['deck_name'] = null;
      }
      final rows = await compute(_prepareRows, <String, Object?>{
        'table': _tables[_tableIndex],
        'mapping': mapping,
        'defaults': _defaults,
        'edits': Map.of(_edits),
      });
      final checks = await compute(_checkRows, <String, Object>{
        'rows': rows,
        'selected': Set.of(_selected),
        'snapshot': _snapshot!,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows = rows;
        _checks = checks;
        _tableGeneration++;
        _groupDirty = false;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = _friendly(e));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _replan() async {
    if (_snapshot == null) return;
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final checks = await compute(_checkRows, <String, Object>{
        'rows': _rows,
        'selected': Set.of(_selected),
        'snapshot': _snapshot!,
      });
      if (mounted && generation == _generation) {
        setState(() {
          _checks = checks;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Bỏ các chỉnh sửa trong bảng?'),
          content: const Text(
            'File gốc và thư viện không thay đổi. Các chỉnh sửa chưa nhập trong lần xem trước này sẽ bị bỏ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Giữ lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Bỏ chỉnh sửa'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _unlock() async {
    if (!await _confirmDiscard() || !mounted) return;
    _edits.clear();
    await _rebuild();
  }

  Future<void> _edit(ImportCheck check) async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ImportRowEditor(check: check),
    );
    if (result == null || !mounted) return;
    _edits[check.row.number] = result;
    await _rebuild();
  }

  Future<void> _export({bool report = false, bool json = false}) async {
    if (_busy || _groupDirty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = _rows.where((r) => _selected.contains(r.number)).toList();
      if (rows.isEmpty) throw const FormatException('Chọn dòng để xuất.');
      if (!report &&
          _checks.any((c) => _selected.contains(c.row.number) && !c.valid)) {
        throw const FormatException(
          'Còn dòng đang chọn bị lỗi/xung đột. Sửa hoặc bỏ chọn trước khi xuất chuẩn hóa.',
        );
      }
      final text = json
          ? jsonEncode({
              'schema_version': '1.0',
              'items': rows.map((r) => r.values).toList(),
            })
          : await compute(_exportPreview, <String, Object>{
              'rows': rows,
              'report': report,
              'messages': {
                for (final c in _checks)
                  c.row.number: '${c.status}: ${c.message}',
              },
            });
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Xuất dữ liệu xem trước',
        fileName:
            'VocabApp-${report ? 'validation' : 'normalized'}.${json ? 'json' : 'csv'}',
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
      if (mounted && saved != null) {
        setState(
          () => _notice = 'Đã xuất file. CSV có bảo vệ công thức bằng dấu nháy đơn; dùng JSON để giữ chuỗi gốc chính xác.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshSnapshot() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _snapshot = await _repo.snapshot();
      if (mounted) await _rebuild();
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    if (_busy || _selected.isEmpty || _groupDirty || _error != null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nhập các dòng đã chọn?'),
        content: Text(
          '${_selected.length} dòng được chọn. ${_approve ? 'Dòng có nghĩa được duyệt để học; dòng thiếu nghĩa vẫn là nháp.' : 'Các nghĩa mới được lưu nháp để duyệt sau.'}\n\nNghĩa hiện có và tiến độ học không bị ghi đè. Nhóm chứa tất cả nghĩa của một từ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Xem lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xác nhận nhập'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _saving = true;
      _error = null;
    });
    try {
      final result = await _repo.commit(
        _rows.where((r) => _selected.contains(r.number)).toList(),
        approve: _approve,
        fileName: _name,
        fileHash: _hash,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã nhập ${result.senses} nghĩa mới, ${result.memberships} liên kết nhóm; ${result.approved} nghĩa được duyệt, ${result.skipped} dòng trùng/đã có được giữ nguyên.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
      try {
        _snapshot = await _repo.snapshot();
        await _replan();
      } catch (_) {
        /* Keep original input visible after a storage failure. */
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _edits.isNotEmpty;
    final selectedChecks = _checks
        .where((c) => _selected.contains(c.row.number))
        .toList();
    final errors = selectedChecks.where((c) => !c.valid).length;
    final ignored = _tables.isEmpty
        ? <String>[]
        : _tables[_tableIndex].columns
              .where(
                (c) =>
                    !_mapping.values.contains(c) ||
                    !_fileGroups &&
                        [
                          _mapping['deck_key'],
                          _mapping['deck_name'],
                        ].contains(c),
              )
              .toList();
    final visible = _onlyProblems
        ? _checks.where((c) => !c.valid || c.warnings.isNotEmpty).toList()
        : _checks;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Nhập và kiểm tra dữ liệu')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'JSON/CSV → chọn danh sách → ánh xạ cột → kiểm tra từng dòng → xác nhận nhập. Chưa có dữ liệu nào được ghi khi xem trước. Không gọi API.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Chọn file JSON / CSV'),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    initialValue: _delimiter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Dấu phân cách CSV',
                    ),
                    items: const [
                      DropdownMenuItem(value: ',', child: Text('Dấu phẩy (,)')),
                      DropdownMenuItem(
                        value: ';',
                        child: Text('Chấm phẩy (;)'),
                      ),
                      DropdownMenuItem(value: '\t', child: Text('Tab')),
                    ],
                    onChanged: locked
                        ? null
                        : (v) async {
                            _delimiter = v!;
                            if (_extension == 'csv' && _bytes != null) {
                              await _read(_bytes!, _name);
                            } else if (mounted) {
                              setState(() {});
                            }
                          },
                  ),
                ),
                if (_name.isNotEmpty) Text(_name),
              ],
            ),
            // Keep the child count fixed: ListView matches children by index,
            // so inserting rows here would reset or jump the widgets below.
            _busy
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LinearProgressIndicator(),
                  )
                : const SizedBox.shrink(),
            _error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
            _notice == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_notice!),
                  ),
            if (_tables.isNotEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _busy ? null : _refreshSnapshot,
                child: const Text('Kiểm tra lại với thư viện hiện tại'),
              ),
              DropdownButtonFormField<int>(
                key: ValueKey('source-$_name-$_tableIndex-${_tables.length}'),
                initialValue: _tableIndex,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Danh sách dữ liệu trong file',
                ),
                items: [
                  for (var i = 0; i < _tables.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${_tables[i].name} (${_tables[i].rows.length} dòng)',
                      ),
                    ),
                ],
                onChanged: locked
                    ? null
                    : (v) {
                        _tableIndex = v!;
                        _mapping = suggestMapping(_tables[v].columns);
                        _mappingOpen = _mapping['term'] == null;
                        _fileGroups =
                            _mapping['deck_key'] != null &&
                            _mapping['deck_name'] != null;
                        _selected = {
                          for (var n = 1; n <= _tables[v].rows.length; n++) n,
                        };
                        _rebuild();
                      },
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                // ListView disposes this tile when it scrolls out of view.
                initiallyExpanded: _mappingOpen,
                onExpansionChanged: (v) => _mappingOpen = v,
                tilePadding: EdgeInsets.zero,
                title: const Text('Ánh xạ cột và giá trị mặc định'),
                children: [
                  const Text(
                    'Cột bỏ trống: ngôn ngữ en → vi, mã nghĩa primary, nhóm đích bên dưới; nghĩa và metadata để trống. Số/boolean/object không tự đổi thành chuỗi.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: importFields
                        .map(
                          (f) => SizedBox(
                            width: 280,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(
                                'map-$_tableIndex-$f-${_mapping[f]}',
                              ),
                              initialValue: _mapping[f] ?? '',
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: importLabels[f],
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text(
                                    'Không ánh xạ / mặc định',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                ..._tables[_tableIndex].columns.map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      columnLabel(c),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: locked
                                  ? null
                                  : (v) {
                                      _mapping[f] = v == '' ? null : v;
                                      _rebuild();
                                    },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              if (ignored.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Cột không được nhập: ${ignored.map(columnLabel).join(', ')}. Có thể ánh xạ sang trường phù hợp ở trên.',
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _fileGroups,
                title: const Text('Dùng mã/tên nhóm từ file'),
                subtitle: const Text(
                  'Tắt để đưa toàn bộ các dòng vào nhóm đích bên dưới.',
                ),
                onChanged: locked
                    ? null
                    : (v) {
                        _fileGroups = v;
                        _rebuild();
                      },
              ),
              if (!_fileGroups) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('target-$_groupKey'),
                  initialValue: _groupKey,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Nhóm đích'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Tạo nhóm mới'),
                    ),
                    ...?_snapshot?.decks.values
                        .where((d) => d['archived'] == 0)
                        .map(
                          (d) => DropdownMenuItem(
                            value: d['deck_key'] as String,
                            child: Text(d['name'] as String),
                          ),
                        ),
                  ],
                  onChanged: locked
                      ? null
                      : (v) {
                          _groupKey = v!;
                          _rebuild();
                        },
                ),
                if (_groupKey.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: _groupName,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        labelText: 'Tên nhóm mới',
                      ),
                      onChanged: (_) => setState(() => _groupDirty = true),
                      onSubmitted: (_) => _rebuild(),
                      onTapOutside: (_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                      },
                    ),
                  ),
              ],
              if (_groupDirty)
                TextButton(
                  onPressed: _busy ? null : _rebuild,
                  child: const Text('Áp dụng tên nhóm và kiểm tra lại'),
                ),
              if (_edits.isNotEmpty)
                TextButton(
                  onPressed: _busy ? null : _unlock,
                  child: Text(
                    'Đổi ánh xạ / nhóm (bỏ ${_edits.length} chỉnh sửa)',
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                '${_rows.length} dòng · ${_selected.length} đang chọn · $errors lỗi/xung đột đang chọn · ${selectedChecks.where((c) => c.status == 'Trùng trong file' || c.status == 'Đã có').length} dòng trùng/đã có',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _selected = _checks
                                .where((c) => c.valid)
                                .map((c) => c.row.number)
                                .toSet();
                            _replan();
                          },
                    child: const Text('Chỉ chọn dòng hợp lệ'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _selected = _rows.map((r) => r.number).toSet();
                            _replan();
                          },
                    child: const Text('Chọn tất cả'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _selected.clear();
                            _replan();
                          },
                    child: const Text('Bỏ chọn tất cả'),
                  ),
                  FilterChip(
                    label: const Text('Chỉ xem lỗi / cảnh báo'),
                    selected: _onlyProblems,
                    onSelected: _busy
                        ? null
                        : (v) => setState(() => _onlyProblems = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ImportGrid(
                key: ValueKey('grid-$_tableGeneration-$_onlyProblems'),
                checks: visible,
                selected: _selected,
                busy: _busy,
                onSelect: (number, value) {
                  if (value) {
                    _selected.add(number);
                  } else {
                    _selected.remove(number);
                  }
                  _replan();
                },
                onEdit: _edit,
              ),
              const SizedBox(height: 16),
              const Text(
                'CSV xuất có bảo vệ công thức Excel bằng dấu nháy đơn cho giá trị bắt đầu = + - @. JSON chuẩn hóa giữ nguyên chuỗi. Nhóm chứa toàn bộ nghĩa của một từ.',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _export(),
                    child: const Text('Xuất CSV chuẩn hóa'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _export(json: true),
                    child: const Text('Xuất JSON chuẩn hóa'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _export(report: true),
                    child: const Text('Xuất báo cáo kiểm tra CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _approve,
                onChanged: _busy ? null : (v) => setState(() => _approve = v!),
                title: const Text('Duyệt những dòng có nghĩa và đưa vào học'),
                subtitle: const Text(
                  'Mặc định lưu nháp. Dòng thiếu nghĩa vẫn là nháp; lịch ôn đã có được giữ nguyên.',
                ),
              ),
              FilledButton(
                onPressed:
                    _busy ||
                        _error != null ||
                        _groupDirty ||
                        _rows.isEmpty ||
                        _selected.isEmpty ||
                        errors > 0
                    ? null
                    : _commit,
                child: const Text('Nhập các dòng đã chọn'),
              ),
              if (_busy && !_saving)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy nhập và quay lại'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportGrid extends StatefulWidget {
  const _ImportGrid({
    super.key,
    required this.checks,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onEdit,
  });
  final List<ImportCheck> checks;
  final Set<int> selected;
  final bool busy;
  final void Function(int, bool) onSelect;
  final void Function(ImportCheck) onEdit;
  @override
  State<_ImportGrid> createState() => _ImportGridState();
}

class _ImportGridState extends State<_ImportGrid> {
  late _ImportSource _source;
  int _pageSize = 10;
  @override
  void initState() {
    super.initState();
    _source = _ImportSource(widget);
  }

  @override
  void didUpdateWidget(_ImportGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _source.update(widget);
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SizedBox(
      width: 1180,
      child: PaginatedDataTable(
        header: Text('${widget.checks.length} dòng trong bảng'),
        rowsPerPage: _pageSize,
        availableRowsPerPage: const [10, 25, 50],
        onRowsPerPageChanged: (v) => setState(() => _pageSize = v!),
        showCheckboxColumn: true,
        onSelectAll: null,
        dataRowMinHeight: 64,
        dataRowMaxHeight: 105,
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('Kiểm tra')),
          DataColumn(label: Text('Từ')),
          DataColumn(label: Text('Nghĩa')),
          DataColumn(label: Text('Nhóm')),
          DataColumn(label: Text('Mã nghĩa')),
          DataColumn(label: Text('Sửa')),
        ],
        source: _source,
      ),
    ),
  );
}

class _ImportSource extends DataTableSource {
  _ImportSource(this.grid);
  _ImportGrid grid;
  void update(_ImportGrid value) {
    grid = value;
    notifyListeners();
  }

  Widget cell(String text, double width) => SizedBox(
    width: width,
    child: Tooltip(
      message: text,
      child: Text(text, maxLines: 4, overflow: TextOverflow.ellipsis),
    ),
  );
  @override
  DataRow? getRow(int index) {
    if (index >= grid.checks.length) return null;
    final c = grid.checks[index], r = grid.checks[index].row;
    return DataRow.byIndex(
      index: index,
      selected: grid.selected.contains(r.number),
      color: c.valid ? null : WidgetStateProperty.all(const Color(0xffffefed)),
      onSelectChanged: grid.busy
          ? null
          : (v) => grid.onSelect(r.number, v ?? false),
      cells: [
        DataCell(Text('${r.number}')),
        DataCell(
          cell('${c.status}${c.message.isEmpty ? '' : '\n${c.message}'}', 270),
        ),
        DataCell(cell(r.display('term'), 130)),
        DataCell(cell(r.display('meaning'), 200)),
        DataCell(cell(r.text('deck_name'), 140)),
        DataCell(cell(r.text('sense_key'), 110)),
        DataCell(
          IconButton(
            tooltip: 'Sửa dòng ${r.number}',
            onPressed: grid.busy ? null : () => grid.onEdit(c),
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
      ],
    );
  }

  @override
  int get rowCount => grid.checks.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount =>
      grid.checks.where((c) => grid.selected.contains(c.row.number)).length;
}

class _ImportRowEditor extends StatefulWidget {
  const _ImportRowEditor({required this.check});
  final ImportCheck check;
  @override
  State<_ImportRowEditor> createState() => _ImportRowEditorState();
}

class _ImportRowEditorState extends State<_ImportRowEditor> {
  late final _fields = {
    for (final f in importFields)
      f: TextEditingController(text: widget.check.row.display(f)),
  };
  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Sửa dòng ${widget.check.row.number}'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.check.message.isNotEmpty) Text(widget.check.message),
            ...importFields.map(
              (f) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: _fields[f],
                  minLines: f == 'meaning' || f == 'note' ? 2 : 1,
                  maxLines: f == 'meaning' || f == 'note' ? 4 : 1,
                  decoration: InputDecoration(labelText: importLabels[f]),
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, <String, Object?>{
          for (final e in _fields.entries) e.key: e.value.text,
        }),
        child: const Text('Áp dụng và kiểm tra lại'),
      ),
    ],
  );
}
