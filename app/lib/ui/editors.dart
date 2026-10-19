import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../domain/models.dart';

String friendlyError(Object error) => error is UserFacingException
    ? error.message
    : 'Không lưu được dữ liệu. Hãy thử lại; nội dung cũ vẫn được giữ.';

Future<String?> askDeckName(BuildContext context, {String? initial}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initial == null ? 'Tạo nhóm từ' : 'Đổi tên nhóm'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(
          labelText: 'Tên nhóm',
          hintText: 'Ví dụ: Công việc',
        ),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.pop(context, v);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text);
            }
          },
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
  // Dialog transitions may still reference the controller after pop.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

class WordEditor extends StatefulWidget {
  const WordEditor({
    super.key,
    required this.repository,
    required this.decks,
    this.word,
    this.initialDeck,
  });
  final LibraryRepository repository;
  final List<Deck> decks;
  final Vocabulary? word;
  final String? initialDeck;
  @override
  State<WordEditor> createState() => _WordEditorState();
}

class _WordEditorState extends State<WordEditor> {
  late final _term = TextEditingController(text: widget.word?.term);
  late final _meaning = TextEditingController(text: widget.word?.meaning);
  final _sense = TextEditingController(text: 'primary');
  late String? _deck = widget.initialDeck ?? widget.decks.firstOrNull?.id;
  bool _busy = false, _reset = false;
  String? _error;
  @override
  void dispose() {
    _term.dispose();
    _meaning.dispose();
    _sense.dispose();
    super.dispose();
  }

  Future<void> _save(bool approve) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.word != null) {
        await widget.repository.saveMeaning(
          widget.word!.senseId,
          _meaning.text,
          approve: approve,
          resetSchedule: _reset,
        );
      } else {
        if (_deck == null) {
          throw const UserFacingException('Tạo một nhóm trước khi thêm từ.');
        }
        await widget.repository.addWord(
          term: _term.text,
          meaning: _meaning.text,
          deckId: _deck!,
          senseKey: _sense.text,
          approve: approve,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.word == null
            ? 'Thêm một từ'
            : 'Sửa nghĩa · ${widget.word!.term}',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.word == null) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tiếng Anh → Tiếng Việt'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _term,
                  autofocus: true,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Từ hoặc cụm từ',
                    hintText: 'Ví dụ: retain',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _deck,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Nhóm từ'),
                  items: widget.decks
                      .map(
                        (d) => DropdownMenuItem(
                          value: d.id,
                          child: Text(d.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _busy ? null : (v) => setState(() => _deck = v),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _meaning,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Nghĩa ngắn',
                  hintText: 'Có thể để trống nếu lưu nháp',
                ),
              ),
              if (widget.word == null)
                ExpansionTile(
                  title: const Text('Thêm nghĩa khác của cùng từ'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    TextField(
                      controller: _sense,
                      maxLength: 64,
                      decoration: const InputDecoration(
                        labelText: 'Mã nghĩa',
                        helperText:
                            'Ví dụ: financial, river_edge. Mặc định: primary.',
                      ),
                    ),
                  ],
                ),
              if (widget.word?.status == 'approved')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reset,
                  onChanged: _busy ? null : (v) => setState(() => _reset = v!),
                  title: const Text('Học lại từ đầu'),
                  subtitle: const Text(
                    'Bật khi đổi nghĩa đáng kể. Lịch sử cũ vẫn được giữ.',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        if (widget.word?.status != 'approved')
          TextButton(
            onPressed: _busy ? null : () => _save(false),
            child: const Text('Lưu nháp'),
          ),
        FilledButton(
          onPressed: _busy ? null : () => _save(true),
          child: Text(_busy ? 'Đang lưu…' : 'Lưu và đưa vào học'),
        ),
      ],
    ),
  );
}

class BulkEditor extends StatefulWidget {
  const BulkEditor({
    super.key,
    required this.repository,
    required this.decks,
    this.initialDeck,
  });
  final LibraryRepository repository;
  final List<Deck> decks;
  final String? initialDeck;
  @override
  State<BulkEditor> createState() => _BulkEditorState();
}

class _BulkEditorState extends State<BulkEditor> {
  final _text = TextEditingController();
  late String? _deck = widget.initialDeck ?? widget.decks.firstOrNull?.id;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_deck == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final count = await widget.repository.addDraftLines(_text.text, _deck!);
      if (mounted) Navigator.pop(context, count);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Dán danh sách từ'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Mỗi dòng một từ hoặc cụm từ, tối đa 500 dòng. Lưu nháp trước, bổ sung nghĩa sau.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _deck,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Nhóm từ'),
                items: widget.decks
                    .map(
                      (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                    )
                    .toList(),
                onChanged: _busy ? null : (v) => setState(() => _deck = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                minLines: 5,
                maxLines: 10,
                maxLength: 100000,
                decoration: const InputDecoration(
                  labelText: 'Danh sách',
                  hintText: 'retain\nresilient\nfollow up',
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _busy || _deck == null ? null : _save,
          child: Text(_busy ? 'Đang lưu…' : 'Lưu nháp'),
        ),
      ],
    ),
  );
}
