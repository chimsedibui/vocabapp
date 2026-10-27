import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../data/library_repository.dart';
import '../domain/models.dart';
import '../domain/scheduler.dart';
import 'editors.dart';
import 'word_details.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.repository, this.deckId});
  final LibraryRepository repository;
  final String? deckId;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final _queue = widget.repository.studyQueue(deckId: widget.deckId);
  int _index = 0;
  bool _revealed = false, _saving = false;
  String _eventId = const Uuid().v4();
  String? _error;

  Future<void> _rate(StudyCard card, Rating rating) async {
    if (!_revealed || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.review(card, rating, _eventId);
      if (mounted) {
        setState(() {
          _index++;
          _revealed = false;
          _saving = false;
          _eventId = const Uuid().v4();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Một từ, một lần nhớ'),
        leading: IconButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          tooltip: 'Tạm dừng',
          icon: const Icon(Icons.close),
        ),
      ),
      body: FutureBuilder<List<StudyCard>>(
        future: _queue,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(friendlyError(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cards = snapshot.data!;
          if (_index >= cards.length) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: Color(0xff21634b),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      cards.isEmpty
                          ? 'Chưa có thẻ cần học'
                          : 'Đã lưu $_index lượt ôn',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Nghỉ một chút. Những từ chưa nhớ sẽ trở lại khi đến hạn.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Về hôm nay'),
                    ),
                  ],
                ),
              ),
            );
          }
          final card = cards[_index];
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.space): () {
                if (!_revealed && !_saving) setState(() => _revealed = true);
              },
              for (var i = 0; i < Rating.values.length; i++)
                SingleActivator(
                  [
                    LogicalKeyboardKey.digit1,
                    LogicalKeyboardKey.digit2,
                    LogicalKeyboardKey.digit3,
                    LogicalKeyboardKey.digit4,
                  ][i],
                ): () =>
                    _rate(card, Rating.values[i]),
            },
            child: Focus(
              autofocus: true,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text('THẺ ${_index + 1} / ${cards.length}'),
                            const Spacer(),
                            Text(card.state == 'new' ? 'Từ mới' : 'Đến hạn ôn'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _index / cards.length,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 32),
                        Card(
                          child: SizedBox(
                            width: double.infinity,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 48,
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'TIẾNG ANH',
                                    style: TextStyle(
                                      letterSpacing: 2,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  SelectableText(
                                    card.term,
                                    style: Theme.of(context)
                                        .textTheme
                                        .displaySmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  WordDetails(
                                    term: card.term,
                                    partOfSpeech: card.partOfSpeech,
                                    pronunciation: card.pronunciation,
                                    alignment: WrapAlignment.center,
                                  ),
                                  const SizedBox(height: 16),
                                  if (_revealed) ...[
                                    const Divider(),
                                    const SizedBox(height: 24),
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        card.meaning,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall,
                                      ),
                                    ),
                                  ] else
                                    const Text(
                                      'Thử nhớ nghĩa trước khi lật thẻ.',
                                      textAlign: TextAlign.center,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (!_revealed)
                          FilledButton.icon(
                            key: const Key('reveal'),
                            onPressed: () => setState(() => _revealed = true),
                            icon: const Icon(Icons.flip_outlined),
                            label: const Text('Hiện nghĩa'),
                          )
                        else ...[
                          const Text('Bạn nhớ từ này thế nào?'),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: Rating.values
                                .map(
                                  (r) => FilledButton.tonal(
                                    onPressed: _saving
                                        ? null
                                        : () => _rate(card, r),
                                    child: Text(r.label),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        if (_saving)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Đang lưu lượt ôn…'),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        const Text(
                          'Không cần chép tay. Không cần gõ đáp án.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
