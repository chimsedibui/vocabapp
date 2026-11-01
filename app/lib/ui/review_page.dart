import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../data/library_repository.dart';
import '../domain/models.dart';
import '../domain/scheduler.dart';
import 'editors.dart';
import 'theme.dart';
import 'word_details.dart';

/// Flashcard session.
///
/// - Tap the card or press Space to flip it, both ways.
/// - Swipe or use ←/→ to move between cards. Rated cards stay viewable; an
///   unrated card that is skipped moves to the end of the session.
/// - 1–4 (or the buttons) rate a card once it has been flipped.
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.repository, this.deckId});
  final LibraryRepository repository;
  final String? deckId;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  static const _swipeDistance = 96.0;
  final _scheduler = Scheduler();
  List<StudyCard>? _cards;
  Object? _loadError;
  int _index = 0;
  bool _flipped = false, _saving = false, _dragging = false;
  double _dx = 0;

  /// +1 when the last move went forward, -1 backward; drives the slide-in.
  int _direction = 1;
  final _rated = <String, Rating>{};

  /// Event ID per card, created on first flip and reused on retry.
  final _events = <String, String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cards = await widget.repository.studyQueue(deckId: widget.deckId);
      if (mounted) {
        setState(() {
          _cards = cards;
          _index = 0;
          _flipped = false;
          _rated.clear();
          _events.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  StudyCard? get _card =>
      _cards != null && _index < _cards!.length ? _cards![_index] : null;

  void _flip() {
    final card = _card;
    if (card == null || _saving) return;
    setState(() {
      _flipped = !_flipped;
      _events.putIfAbsent(card.id, () => const Uuid().v4());
    });
  }

  void _go(int step) {
    final cards = _cards, card = _card;
    if (cards == null || card == null || _saving) return;
    setState(() {
      _error = null;
      _flipped = false;
      _direction = step;
      if (step < 0) {
        if (_index > 0) _index--;
      } else if (_rated.containsKey(card.id)) {
        _index++;
      } else if (_index < cards.length - 1) {
        // Skipped: see it again at the end of the session.
        cards.add(cards.removeAt(_index));
      }
    });
  }

  Future<void> _rate(Rating rating) async {
    final card = _card;
    if (card == null ||
        _saving ||
        !_events.containsKey(card.id) ||
        _rated.containsKey(card.id)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.review(card, rating, _events[card.id]!);
      if (mounted) {
        setState(() {
          _rated[card.id] = rating;
          _saving = false;
          _flipped = false;
          _direction = 1;
          _index++;
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

  String _interval(StudyCard card, Rating rating) {
    final now = DateTime.now().toUtc();
    final next = _scheduler.review(
      state: card.state,
      intervalDays: card.intervalDays,
      lapses: card.lapses,
      rating: rating,
      now: now,
    );
    final minutes = next.due.difference(now).inMinutes;
    return minutes < 60 ? '$minutes phút' : '${next.intervalDays} ngày';
  }

  bool get _touch => switch (Theme.of(context).platform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

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
      body: _body(),
    ),
  );

  Widget _body() {
    if (_loadError != null) {
      return Center(child: Text(friendlyError(_loadError!)));
    }
    final cards = _cards;
    if (cards == null) return const Center(child: CircularProgressIndicator());
    final card = _card;
    if (card == null) return _finished(cards);
    final rated = _rated[card.id];
    final seen = _events.containsKey(card.id);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _flip,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        for (final (i, keys) in const [
          [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
          [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
          [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
          [LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4],
        ].indexed)
          for (final key in keys)
            SingleActivator(key): () => _rate(Rating.values[i]),
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _header(cards),
                const SizedBox(height: 20),
                _swipeable(card),
                const SizedBox(height: 20),
                if (rated != null)
                  Text(
                    'Đã đánh giá: ${rated.label}. Nhấn → để sang thẻ tiếp.',
                    textAlign: TextAlign.center,
                  )
                else if (!seen)
                  Center(
                    child: FilledButton.icon(
                      key: const Key('reveal'),
                      onPressed: _flip,
                      icon: const Icon(Icons.flip_outlined),
                      label: const Text('Lật thẻ'),
                    ),
                  )
                else
                  _ratings(card),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Đang lưu lượt ôn…',
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                _navigation(cards),
                const SizedBox(height: 12),
                Text(
                  _touch
                      ? 'Chạm thẻ để lật · vuốt trái/phải để chuyển thẻ'
                      : 'Space lật thẻ · ← → chuyển thẻ · 1–4 đánh giá',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.of(context).muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(List<StudyCard> cards) => Column(
    children: [
      Row(
        children: [
          Text('THẺ ${_index + 1} / ${cards.length}'),
          const Spacer(),
          Text('Đã đánh giá ${_rated.length}'),
        ],
      ),
      const SizedBox(height: 10),
      LinearProgressIndicator(
        value: cards.isEmpty ? 0 : _rated.length / cards.length,
        minHeight: 4,
        borderRadius: BorderRadius.circular(4),
      ),
    ],
  );

  /// Drag follows the finger with a slight tilt; past [_swipeDistance] (or a
  /// fast fling) it changes card, otherwise it springs back.
  Widget _swipeable(StudyCard card) => GestureDetector(
    onTap: _flip,
    onHorizontalDragStart: (_) => setState(() => _dragging = true),
    onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
    onHorizontalDragEnd: (d) {
      final velocity = d.primaryVelocity ?? 0;
      final step = _dx < -_swipeDistance || velocity < -800
          ? 1
          : _dx > _swipeDistance || velocity > 800
          ? -1
          : 0;
      setState(() {
        _dragging = false;
        _dx = 0;
      });
      if (step != 0) _go(step);
    },
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: _dx),
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, dx, child) => Transform.translate(
        offset: Offset(dx, 0),
        child: Transform.rotate(angle: dx / 1200, child: child),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween(
            begin: Offset(0.25 * _direction, 0),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        layoutBuilder: (current, previous) => Stack(children: [?current]),
        child: _FlipCard(
          key: ValueKey(card.id),
          flipped: _flipped,
          front: _front(card),
          back: _back(card),
        ),
      ),
    ),
  );

  Widget _face({required Widget child, Color? color}) => SizedBox(
    height: 300,
    width: double.infinity,
    child: Card(
      color: color,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: SingleChildScrollView(child: child)),
      ),
    ),
  );

  Widget _badge(String text) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.of(context).controlHover,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(text, style: Theme.of(context).code),
    ),
  );

  Widget _front(StudyCard card) => _face(
    child: Column(
      children: [
        _badge(card.state == 'new' ? 'TỪ MỚI' : 'ÔN LẠI'),
        const SizedBox(height: 20),
        Text(
          card.term,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        WordDetails(
          term: card.term,
          partOfSpeech: card.partOfSpeech,
          pronunciation: card.pronunciation,
          alignment: WrapAlignment.center,
        ),
      ],
    ),
  );

  Widget _back(StudyCard card) => _face(
    color: AppColors.of(context).raisedTinted,
    child: Column(
      children: [
        Text(
          [
            card.term,
            if (partOfSpeechAbbreviations[card.partOfSpeech] case final pos?)
              '($pos)',
          ].join(' '),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.of(context).muted),
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            card.meaning,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );

  Widget _ratings(StudyCard card) {
    final colors = AppColors.of(context);
    final tones = {
      Rating.again: colors.danger,
      Rating.hard: Colors.orange.shade700,
      Rating.good: colors.accent,
      Rating.easy: Colors.green.shade600,
    };
    return Row(
      children: [
        for (final (i, r) in Rating.values.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: tones[r],
                side: BorderSide(color: tones[r]!.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _saving ? null : () => _rate(r),
              child: Column(
                children: [
                  Text(
                    r.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _touch
                        ? _interval(card, r)
                        : '${i + 1} · ${_interval(card, r)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _navigation(List<StudyCard> cards) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: 'Thẻ trước (←)',
        onPressed: _index > 0 && !_saving ? () => _go(-1) : null,
        icon: const Icon(Icons.chevron_left),
      ),
      if (_events.containsKey(_card!.id))
        TextButton.icon(
          onPressed: _saving ? null : _flip,
          icon: const Icon(Icons.flip_outlined),
          label: Text(_flipped ? 'Xem mặt trước' : 'Xem nghĩa'),
        ),
      IconButton(
        tooltip: _rated.containsKey(_card!.id)
            ? 'Thẻ tiếp (→)'
            : 'Bỏ qua, xem lại cuối phiên (→)',
        onPressed: !_saving ? () => _go(1) : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  Widget _finished(List<StudyCard> cards) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: AppColors.of(context).accent,
          ),
          const SizedBox(height: 24),
          Text(
            cards.isEmpty
                ? 'Chưa có thẻ cần học'
                : 'Đã lưu ${_rated.length} lượt ôn',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Nghỉ một chút. Những từ chưa nhớ sẽ trở lại khi đến hạn.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              if (cards.isNotEmpty) ...[
                OutlinedButton(
                  onPressed: () => setState(() {
                    _index = max(0, cards.length - 1);
                    _direction = -1;
                  }),
                  child: const Text('Xem lại thẻ vừa học'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() => _cards = null);
                    _load();
                  },
                  child: const Text('Học tiếp'),
                ),
              ],
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Về hôm nay'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Turns around the vertical axis; the back face is counter-rotated so its
/// text is not mirrored.
class _FlipCard extends StatelessWidget {
  const _FlipCard({
    super.key,
    required this.flipped,
    required this.front,
    required this.back,
  });
  final bool flipped;
  final Widget front, back;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: flipped ? pi : 0),
    duration: const Duration(milliseconds: 320),
    curve: Curves.easeInOut,
    builder: (context, angle, _) {
      final showBack = angle > pi / 2;
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(angle),
        child: showBack
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(pi),
                child: back,
              )
            : front,
      );
    },
  );
}
