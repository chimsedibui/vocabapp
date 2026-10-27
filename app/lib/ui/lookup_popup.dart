import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/library_repository.dart';
import '../data/passage_repository.dart';
import '../domain/models.dart';
import '../domain/passage.dart';
import '../services/ai_configuration.dart';
import '../services/passage_service.dart';
import 'editors.dart';
import 'word_details.dart';

/// Small window opened by the selection hotkey. Library matches show
/// offline; new text goes through the passage flow (cache first, one part),
/// so lookups are kept in history and adding reuses passage approval.
class LookupPopup extends StatefulWidget {
  const LookupPopup({
    super.key,
    required this.library,
    required this.text,
    required this.onClose,
    required this.onOpenApp,
    this.serviceFactory,
  });
  final LibraryRepository library;
  final String? text;
  final VoidCallback onClose, onOpenApp;
  final PassageService Function()? serviceFactory;
  @override
  State<LookupPopup> createState() => _LookupPopupState();
}

class _LookupPopupState extends State<LookupPopup> {
  late final _repo = PassageRepository(widget.library);
  late final _input = TextEditingController(text: widget.text?.trim() ?? '');
  List<Deck> _decks = [];
  String? _deck, _jobId, _error, _note;
  List<Vocabulary> _known = [];
  List<PassageItem> _items = [];
  final _added = <PassageItem>{};
  PassageService? _service;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void dispose() {
    _service?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final text = normalizeMeaning(_input.text);
    setState(() {
      _busy = true;
      _error = _note = _jobId = null;
      _known = [];
      _items = [];
      _added.clear();
    });
    try {
      if (_decks.isEmpty) {
        _decks = await widget.library.decks();
        _deck = _decks.firstOrNull?.id;
      }
      if (text.isEmpty) {
        throw const UserFacingException(
          'Không lấy được chữ đang bôi đen. Gõ từ cần tra rồi nhấn Enter.',
        );
      }
      if (utf8.encode(text).length > maxPartBytes) {
        throw const UserFacingException(
          'Đoạn chọn quá dài cho popup. Mở app → Từ passage để trích cả đoạn.',
        );
      }
      final words = text.split(RegExp(r'\s+')).length;
      if (words <= 4) _known = await _repo.matches(text);
      AiPreferences? prefs;
      try {
        prefs = await const AiConfigurationStore().load();
      } catch (_) {
        /* Treated as not configured. */
      }
      if (prefs == null) {
        _note = 'Cấu hình API trong app để tra nghĩa mới.';
        return;
      }
      final request = PassageRequest(
        text,
        minLevel: 'A1',
        maxItems: words <= 4 ? 3 : 15,
      );
      final key = request.cacheKey(prefs.identity);
      var id = await _repo.cached(key);
      if (id == null) {
        id = await _repo.create(request, prefs);
        final jobId = id;
        _service = widget.serviceFactory?.call() ?? PassageService();
        final response = await _service!.extractParts(
          request,
          prefs,
          onAttempt: (a) => _repo.attempt(jobId, a),
        );
        if (response.done.isEmpty) {
          await _repo.fail(jobId, response.error!);
          throw response.error!;
        }
        await _repo.completeParts(jobId, response);
      }
      final row = await _repo.job(id);
      _jobId = id;
      _items = validatePassageResult(
        row['result_json'] as String,
        request,
      ).items;
      if (_items.isEmpty) _note = 'AI không trả nghĩa nào cho đoạn này.';
    } catch (e) {
      _error = friendlyError(e);
    } finally {
      _service = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(PassageItem item) async {
    final deck = _deck, job = _jobId;
    if (deck == null || job == null) return;
    setState(() => _busy = true);
    try {
      await _repo.approve(job, deck, [ReviewedItem(item)]);
      _added.add(item);
      _known = await _repo.matches(item.term);
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      autofocus: true,
                      enabled: !_busy,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _lookup(),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Tra từ',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng (Esc)',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(right: 8),
                  children: [
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    if (_known.isNotEmpty) ...[
                      Text(
                        'Đã có trong thư viện',
                        style: theme.textTheme.labelLarge,
                      ),
                      for (final v in _known)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.check_circle_outline),
                          title: Text(v.term),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              WordDetails(
                                term: v.term,
                                partOfSpeech: v.partOfSpeech,
                                pronunciation: v.pronunciation,
                              ),
                              Text(v.meaning),
                            ],
                          ),
                        ),
                      const Divider(),
                    ],
                    for (final item in _items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${item.term} · ${item.level}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            WordDetails(
                              term: item.term,
                              partOfSpeech: item.partOfSpeech,
                              pronunciation: item.pronunciation,
                            ),
                            Text(item.meaning),
                          ],
                        ),
                        trailing: _added.contains(item)
                            ? const Icon(Icons.done)
                            : IconButton(
                                tooltip: 'Thêm vào nhóm',
                                onPressed: _busy || _deck == null
                                    ? null
                                    : () => _add(item),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                      ),
                    if (_note != null) Text(_note!),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _deck,
                      hint: const Text('Chọn nhóm'),
                      items: [
                        for (final d in _decks)
                          DropdownMenuItem(
                            value: d.id,
                            child: Text(
                              d.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _deck = v),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onOpenApp,
                    child: const Text('Mở app'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
