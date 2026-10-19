import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/library_repository.dart';
import '../data/passage_repository.dart';
import '../domain/models.dart';
import '../domain/passage.dart';
import '../services/ai_configuration.dart';
import '../services/passage_service.dart';
import 'ai_settings.dart';
import 'editors.dart';

class PassagePage extends StatefulWidget {
  const PassagePage({
    super.key,
    required this.library,
    this.initialDeck,
    this.serviceFactory,
  });
  final LibraryRepository library;
  final String? initialDeck;
  final PassageService Function()? serviceFactory;
  @override
  State<PassagePage> createState() => _PassagePageState();
}

class _Proposal {
  _Proposal(PassageItem item)
    : term = item.term,
      level = item.level,
      meaning = TextEditingController(text: item.meaning);
  final String term;
  String level;
  final TextEditingController meaning;
  bool selected = true;
  List<Vocabulary> matches = [];
  String? existingSense;
  PassageItem get item => PassageItem(term, level, meaning.text);
}

class _PassagePageState extends State<PassagePage> {
  late final _repo = PassageRepository(widget.library);
  final _text = TextEditingController();
  final _max = TextEditingController(text: '30');
  String _level = 'B1';
  String? _deck, _jobId, _error;
  List<Deck> _decks = [];
  List<Map<String, Object?>> _history = [];
  List<_Proposal> _proposals = [];
  AiPreferences? _preferences;
  PassageService? _service;
  bool _busy = true, _loadedResult = false, _atLimit = false;
  int _removed = 0;
  String? _resultLabel;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final decks = await widget.library.decks();
      final history = await _repo.history();
      final preferences = await const AiConfigurationStore().load();
      if (!mounted) return;
      setState(() {
        _decks = decks;
        _history = history;
        _preferences = preferences;
        _deck ??= decks.any((d) => d.id == widget.initialDeck)
            ? widget.initialDeck
            : decks.firstOrNull?.id;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _service?.cancel();
    _text.dispose();
    _max.dispose();
    for (final p in _proposals) {
      p.meaning.dispose();
    }
    super.dispose();
  }

  Future<void> _configure() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const AiSettingsPage()),
    );
    if (mounted) {
      setState(() => _busy = true);
      await _load();
    }
  }

  Future<void> _newDeck() async {
    final name = await askDeckName(context);
    if (name == null || !mounted) return;
    try {
      final id = await widget.library.createDeck(name);
      if (!mounted) return;
      _deck = id;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _clearResult() {
    for (final p in _proposals) {
      p.meaning.dispose();
    }
    _proposals = [];
    _loadedResult = false;
    _jobId = null;
    _resultLabel = null;
  }

  Future<void> _showJob(String id, {bool cached = false}) async {
    final row = await _repo.job(id);
    final request = PassageRequest(
      row['source_text'] as String,
      minLevel: row['min_level'] as String,
      maxItems: row['max_items'] as int,
    );
    final proposals = <_Proposal>[];
    if (row['status'] == 'complete') {
      final result = validatePassageResult(
        row['result_json'] as String,
        request,
      );
      for (final item in result.items) {
        final proposal = _Proposal(item);
        proposal.matches = await _repo.matches(item.term);
        proposals.add(proposal);
      }
    }
    if (!mounted) {
      for (final p in proposals) {
        p.meaning.dispose();
      }
      return;
    }
    _clearResult();
    setState(() {
      _text.text = request.text;
      _level = request.minLevel;
      _max.text = '${request.maxItems}';
      _jobId = id;
      _proposals = proposals;
      _loadedResult = row['status'] == 'complete';
      _removed = row['removed'] as int;
      _atLimit = row['at_limit'] == 1;
      _resultLabel =
          '${row['provider'] ?? 'Chưa có kết quả'} / ${row['model'] ?? ''}${cached ? ' · cache, không gọi API' : ''}';
      _error = row['error_text'] as String?;
      if (row['status'] == 'pending') {
        _error = 'Lần trước chưa hoàn tất. Bạn có thể trích lại passage này.';
      }
    });
  }

  Future<void> _extract({bool regenerate = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? jobId;
    try {
      final prefs = _preferences;
      if (prefs == null) {
        throw const UserFacingException('Cấu hình API trước khi trích từ.');
      }
      final request = PassageRequest(
        _text.text,
        minLevel: _level,
        maxItems: int.tryParse(_max.text) ?? 0,
      );
      request.checkBudget(prefs.primary.contextWindow);
      if (prefs.fallback != null) {
        request.checkBudget(prefs.fallback!.contextWindow);
      }
      final cached = regenerate
          ? null
          : await _repo.cached(request.cacheKey(prefs.identity));
      if (cached != null) {
        await _showJob(cached, cached: true);
        return;
      }
      jobId = await _repo.create(request, prefs);
      if (!mounted) {
        throw const PassageCancelled();
      }
      setState(
        () => _service = widget.serviceFactory?.call() ?? PassageService(),
      );
      final response = await _service!.extract(
        request,
        prefs,
        onAttempt: (a) => _repo.attempt(jobId!, a),
      );
      await _repo.complete(jobId, response);
      await _showJob(jobId);
    } catch (e) {
      final error = e is UserFacingException
          ? e
          : const UserFacingException(
              'Không xử lý được passage. Nội dung nhập vẫn được giữ.',
            );
      if (jobId != null) {
        try {
          await _repo.fail(jobId, error);
        } catch (_) {
          /* Keep input in the editor even if storage fails. */
        }
      }
      if (mounted) setState(() => _error = error.message);
    } finally {
      _service = null;
      if (mounted) {
        try {
          final history = await _repo.history();
          if (mounted) setState(() => _history = history);
        } catch (_) {
          /* Existing input is still visible. */
        }
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _openHistory(String id) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _showJob(id);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _deleteHistory(String id) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa passage khỏi thiết bị?'),
        content: const Text(
          'Xóa văn bản nguồn, kết quả và usage của job này. Các từ đã lưu và lịch ôn được giữ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa passage'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.delete(id);
      if (mounted && _jobId == id) {
        setState(() {
          _clearResult();
          _text.clear();
        });
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _busy = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _jobId == null || _deck == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final count = await _repo.approve(
        _jobId!,
        _deck!,
        _proposals
            .where((p) => p.selected)
            .map((p) => ReviewedItem(p.item, existingSenseId: p.existingSense))
            .toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã duyệt: $count nghĩa mới đưa vào học; nghĩa trùng được gắn nhóm và giữ lịch ôn.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _busy = false;
        });
      }
    }
  }

  Future<void> _json() async {
    final json = jsonEncode({
      'items': _proposals
          .where((p) => p.selected)
          .map((p) => p.item.toJson())
          .toList(),
    });
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('JSON các mục đã chọn'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(child: SelectableText(json)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('Copy JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _usage() async {
    if (_jobId == null) return;
    try {
      final row = await _repo.job(_jobId!);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Usage theo lần gọi'),
          content: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ')
                  .convert(jsonDecode(row['attempts_json'] as String)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Widget _proposal(_Proposal p) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: p.selected,
            onChanged: _busy ? null : (v) => setState(() => p.selected = v!),
            title: Text(
              p.term,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${p.level} · mức ước lượng${p.matches.isEmpty ? '' : ' · đã có ${p.matches.length} nghĩa trong thư viện'}',
            ),
          ),
          TextField(
            controller: p.meaning,
            enabled: !_busy && p.existingSense == null,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Nghĩa ngắn · có thể sửa',
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: p.level,
            decoration: const InputDecoration(labelText: 'Mức CEFR ước lượng'),
            items: cefrLevels
                .where(
                  (l) => cefrLevels.indexOf(l) >= cefrLevels.indexOf(_level),
                )
                .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                .toList(),
            onChanged: _busy ? null : (v) => setState(() => p.level = v!),
          ),
          if (p.matches.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: p.existingSense ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Xử lý từ đã có'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Dùng nghĩa đề xuất (trùng thì gắn nhóm)'),
                ),
                ...p.matches
                    .where((v) => v.status == 'approved')
                    .map(
                      (v) => DropdownMenuItem(
                        value: v.senseId,
                        child: Text(
                          'Giữ nghĩa: ${v.meaning}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => p.existingSense = v == '' ? null : v),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    int? estimate;
    try {
      estimate = PassageRequest(
        _text.text,
        minLevel: _level,
        maxItems: int.tryParse(_max.text) ?? 0,
      ).estimatedInputTokens;
    } catch (_) {
      /* Validation happens before send. */
    }
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Thêm từ từ passage')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Dán tiếng Anh → trích nghĩa tiếng Việt → duyệt trước khi học. Mức CEFR do AI ước lượng; bạn có thể sửa hoặc bỏ từng mục.',
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _preferences == null
                        ? 'Chưa cấu hình API'
                        : '${_preferences!.primary.label} / ${_preferences!.primary.model}',
                  ),
                  subtitle: Text(
                    _preferences?.fallback == null
                        ? 'Chưa bật dịch vụ dự phòng'
                        : 'Dự phòng: ${_preferences!.fallback!.label} / ${_preferences!.fallback!.model}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Cấu hình API',
                    onPressed: _busy ? null : _configure,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ),
                TextField(
                  controller: _text,
                  enabled: !_busy && !_loadedResult,
                  minLines: 5,
                  maxLines: 12,
                  maxLength: 12000,
                  decoration: const InputDecoration(
                    labelText: 'Passage tiếng Anh',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('threshold-$_level'),
                  initialValue: _level,
                  decoration: const InputDecoration(labelText: 'Mức tối thiểu'),
                  items: cefrLevels
                      .map(
                        (l) => DropdownMenuItem(
                          value: l,
                          child: Text('$l trở lên'),
                        ),
                      )
                      .toList(),
                  onChanged: _busy || _loadedResult
                      ? null
                      : (v) => setState(() => _level = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _max,
                  enabled: !_busy && !_loadedResult,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số mục tối đa (1–100)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Text(
                  'Input ước tính bảo thủ: ${estimate ?? '—'} / 4.000 tokens; output cap: 2.500 tokens. Một lần bấm có thể gọi tối đa 3 HTTP attempts, trong 120 giây. Không tự chia đoạn hoặc gọi tiếp.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy || _preferences == null
                          ? null
                          : () => _extract(),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(
                        _busy ? 'Đang xử lý…' : 'Trích từ (ưu tiên cache)',
                      ),
                    ),
                    if (_busy && _service != null)
                      OutlinedButton(
                        onPressed: () => _service?.cancel(),
                        child: const Text('Hủy gọi API'),
                      ),
                    if (_loadedResult && !_busy) ...[
                      TextButton(
                        onPressed: () => _extract(regenerate: true),
                        child: const Text('Tạo lại bằng API'),
                      ),
                      TextButton(
                        onPressed: () => setState(_clearResult),
                        child: const Text('Sửa passage / tạo mới'),
                      ),
                    ],
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_loadedResult) ...[
                  const Divider(height: 32),
                  Text('${_proposals.length} mục · $_resultLabel'),
                  Text(
                    'Đã loại $_removed mục ngoài nguồn, dưới ngưỡng hoặc trùng. Kết quả vẫn chờ bạn duyệt.',
                  ),
                  if (_atLimit)
                    const Text(
                      'Đã đạt giới hạn số mục; passage có thể còn từ khác.',
                    ),
                  if (_proposals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Không tìm thấy mục phù hợp. App không tự gọi lại.',
                      ),
                    ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: _busy ? null : _json,
                        child: const Text('Xem / copy JSON'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _usage,
                        child: const Text('Xem usage'),
                      ),
                    ],
                  ),
                  ..._proposals.map(_proposal),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey('deck-$_deck-${_decks.length}'),
                    initialValue: _deck,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Lưu vào nhóm',
                    ),
                    items: _decks
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(d.name),
                          ),
                        )
                        .toList(),
                    onChanged: _busy ? null : (v) => setState(() => _deck = v),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _newDeck,
                    child: const Text('Tạo nhóm mới'),
                  ),
                  FilledButton(
                    onPressed:
                        _busy ||
                            _deck == null ||
                            !_proposals.any((p) => p.selected)
                        ? null
                        : _save,
                    child: const Text('Duyệt các mục đã chọn và đưa vào học'),
                  ),
                ],
                const Divider(height: 40),
                Text(
                  'Passage đã lưu trên thiết bị',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Giữ văn bản nguồn để thử lại hoặc duyệt sau. Backup có chứa passage. Xóa passage không xóa từ đã học.',
                ),
                ..._history.map(
                  (row) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${row['min_level']}+ · ${row['status']} · ${row['provider'] ?? 'chưa hoàn tất'}',
                    ),
                    subtitle: Text(
                      DateTime.fromMillisecondsSinceEpoch(
                        row['created_at'] as int,
                      ).toLocal().toString(),
                    ),
                    onTap: _busy
                        ? null
                        : () => _openHistory(row['id'] as String),
                    trailing: IconButton(
                      tooltip: 'Xóa passage',
                      onPressed: _busy
                          ? null
                          : () => _deleteHistory(row['id'] as String),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
