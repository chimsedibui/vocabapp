import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../data/library_repository.dart';
import '../domain/models.dart';
import '../domain/scheduler.dart';
import '../services/speech.dart';
import '../services/sync_service.dart';
import 'editors.dart';
import 'theme.dart';
import 'word_details.dart';

/// Flashcard session.
///
/// - Tap the card or press Space to flip it, both ways.
/// - Swipe or use ←/→ to move between cards. Rated cards stay viewable;
///   skipped ones are offered again on the summary.
/// - 1–5 (or the buttons) rate a card once it has been flipped; Z undoes the
///   last rating; R reads the word aloud.
/// - A card due again within [requeueWithin] comes back later in the same
///   session, after the other cards, once its time is up.
class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.repository,
    this.deckId,
    this.sync,
  });
  final LibraryRepository repository;
  final String? deckId;
  final SyncService? sync;
  static const requeueWithin = Duration(hours: 1);
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

  /// Session state is per slot (index in [_cards]): a requeued card gets a
  /// new slot with its updated snapshot.
  final _rated = <int, Rating>{};

  /// Event ID per slot, created on first flip and reused on retry.
  final _events = <int, String>{};

  /// When requeued slots become due.
  final _dueAt = <int, DateTime>{};

  /// Analytics timing per slot: when the front was last shown before the
  /// first flip, and when the answer was first revealed.
  final _shownAt = <int, DateTime>{};
  final _flippedAt = <int, DateTime>{};

  /// Reviews after a pause longer than [_sessionGap] start a new session.
  static const _sessionGap = Duration(minutes: 5);
  String _session = const Uuid().v4();
  DateTime? _lastRated;

  /// The last rating, while it can still be undone.
  ({int slot, StudyCard before, String event, int? requeued})? _last;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// On the summary, counts down and opens a requeued card once it is due.
  void _onTick() {
    if (!mounted || _card != null || _dueAt.isEmpty) return;
    setState(() {
      final due = _dueAt.keys.where((i) => !_rated.containsKey(i) && _ready(i));
      if (due.isNotEmpty) {
        _show(due.reduce(min));
        _direction = 1;
      }
    });
  }

  Future<void> _load() async {
    try {
      // Pull the other device's reviews first so the same card is not studied
      // twice; a slow or offline server must not hold up the session.
      await widget.sync?.sync().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      final cards = await widget.repository.studyQueue(deckId: widget.deckId);
      if (mounted) {
        setState(() {
          _cards = cards;
          _flipped = false;
          _rated.clear();
          _events.clear();
          _dueAt.clear();
          _shownAt.clear();
          _flippedAt.clear();
          _show(0);
          _last = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _show(int slot) {
    _index = slot;
    if (!_events.containsKey(slot)) _shownAt[slot] = DateTime.now();
  }

  StudyCard? get _card =>
      _cards != null && _index < _cards!.length ? _cards![_index] : null;

  Future<void> _speak() async {
    final card = _card;
    if (card == null) return;
    if (!await Speech.speak(card.term) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thiết bị chưa có giọng đọc tiếng Anh.')),
      );
    }
  }

  void _flip() {
    final card = _card;
    if (card == null || _saving) return;
    setState(() {
      _flipped = !_flipped;
      _events.putIfAbsent(_index, () => const Uuid().v4());
      _flippedAt.putIfAbsent(_index, DateTime.now);
    });
  }

  void _go(int step) {
    final cards = _cards;
    if (cards == null || _saving) return;
    setState(() {
      _error = null;
      _flipped = false;
      _direction = step;
      // Requeued cards that are not due yet are passed over. Past the last
      // card is the summary, which offers skipped cards again.
      var i = _index + step;
      while (i >= 0 &&
          i < cards.length &&
          !_rated.containsKey(i) &&
          !_ready(i)) {
        i += step;
      }
      _show(i.clamp(0, cards.length));
    });
  }

  bool _ready(int slot) => !(_dueAt[slot]?.isAfter(DateTime.now()) ?? false);

  /// Unrated slots that can be studied now, in session order.
  List<int> get _skipped => [
    for (var i = 0; i < (_cards?.length ?? 0); i++)
      if (!_rated.containsKey(i) && _ready(i)) i,
  ];

  /// Requeued slots still waiting for their time.
  List<int> get _waiting => [
    for (final i in _dueAt.keys)
      if (!_rated.containsKey(i) && !_ready(i)) i,
  ];

  Future<void> _rate(Rating rating) async {
    final card = _card;
    if (card == null ||
        _saving ||
        !_events.containsKey(_index) ||
        _rated.containsKey(_index)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      if (_lastRated case final last? when now.difference(last) > _sessionGap) {
        _session = const Uuid().v4();
      }
      final next = await widget.repository.review(
        card,
        rating,
        _events[_index]!,
        sessionId: _session,
        shownAt: _shownAt[_index],
        flippedAt: _flippedAt[_index],
      );
      _lastRated = now;
      widget.sync?.requestSync();
      if (mounted) {
        setState(() {
          _rated[_index] = rating;
          int? requeued;
          if (next != null &&
              next.due.difference(DateTime.now()) <= ReviewPage.requeueWithin) {
            requeued = _cards!.length;
            _dueAt[requeued] = next.due;
            _cards!.add(
              card.copyWith(
                state: next.state,
                intervalDays: next.intervalDays,
                lapses: next.lapses,
                revision: card.revision + 1,
              ),
            );
          }
          _last = next == null
              ? null
              : (
                  slot: _index,
                  before: card,
                  event: _events[_index]!,
                  requeued: requeued,
                );
          _saving = false;
          _flipped = false;
          _direction = 1;
          // Next unrated card; the summary when none are left after this one.
          _show(
            _skipped.firstWhere(
              (i) => i > _index,
              orElse: () => _cards!.length,
            ),
          );
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

  Future<void> _undo() async {
    final last = _last;
    if (last == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final card = await widget.repository.undoReview(last.before, last.event);
      widget.sync?.requestSync();
      if (mounted) {
        setState(() {
          // The requeued copy is always the newest slot.
          if (last.requeued case final slot? when slot == _cards!.length - 1) {
            _cards!.removeLast();
            _dueAt.remove(slot);
            _events.remove(slot);
          }
          _cards![last.slot] = card;
          _rated.remove(last.slot);
          _events[last.slot] = const Uuid().v4();
          _index = last.slot;
          _flipped = true;
          _direction = -1;
          _last = null;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _saving = false;
          _last = null;
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
    final wait = next.due.difference(now);
    if (wait < const Duration(hours: 1)) return '${wait.inMinutes} phút';
    if (wait < const Duration(days: 1)) return '${wait.inHours} giờ';
    return '${next.intervalDays} ngày';
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
    final rated = _rated[_index];
    final seen = _events.containsKey(_index);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _flip,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.keyZ): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyR): _speak,
        for (final (i, keys) in const [
          [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
          [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
          [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
          [LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4],
          [LogicalKeyboardKey.digit5, LogicalKeyboardKey.numpad5],
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
                  _touch ? 'Chạm thẻ để lật · vuốt trái/phải để chuyển thẻ' : 'Space lật thẻ · ← → chuyển thẻ · 1–5 đánh giá · Z hoàn tác · R đọc từ',
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
          Text('Còn ${cards.length - _rated.length} thẻ'),
          const Spacer(),
          if (_waiting.isNotEmpty)
            Text(
              '${_waiting.length} thẻ chờ quay lại',
              style: TextStyle(color: AppColors.of(context).muted),
            ),
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
          key: ValueKey(_index),
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
        if (card.note case final note? when note.isNotEmpty) ...[
          const SizedBox(height: 16),
          ExampleText(
            note,
            term: card.term,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ],
    ),
  );

  Widget _ratings(StudyCard card) {
    final colors = AppColors.of(context);
    final tones = {
      Rating.again: colors.danger,
      Rating.hard: Colors.orange.shade700,
      Rating.okay: Colors.amber.shade800,
      Rating.good: colors.accent,
      Rating.easy: Colors.green.shade600,
    };
    Widget button(int i, Rating r) => OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: tones[r],
        side: BorderSide(color: tones[r]!.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: _saving ? null : () => _rate(r),
      child: Column(
        children: [
          Text(r.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            _touch ? _interval(card, r) : '${i + 1} · ${_interval(card, r)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
    Widget row(Iterable<(int, Rating)> items) => Row(
      children: [
        for (final (n, (i, r)) in items.indexed) ...[
          if (n > 0) const SizedBox(width: 8),
          Expanded(child: button(i, r)),
        ],
      ],
    );
    final all = Rating.values.indexed.toList();
    // Five buttons in one row get too narrow on phones: 3 + 2 instead.
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 440
          ? row(all)
          : Column(
              children: [
                row(all.take(3)),
                const SizedBox(height: 8),
                row(all.skip(3)),
              ],
            ),
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
      if (_last != null)
        IconButton(
          tooltip: 'Hoàn tác lượt vừa chấm (Z)',
          onPressed: _saving ? null : _undo,
          icon: const Icon(Icons.undo),
        ),
      if (_events.containsKey(_index))
        TextButton.icon(
          onPressed: _saving ? null : _flip,
          icon: const Icon(Icons.flip_outlined),
          label: Text(_flipped ? 'Xem mặt trước' : 'Xem nghĩa'),
        ),
      IconButton(
        tooltip: _rated.containsKey(_index) ? 'Thẻ tiếp (→)' : 'Bỏ qua (→)',
        onPressed: !_saving ? () => _go(1) : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  String _countdown() {
    final next = _waiting
        .map((i) => _dueAt[i]!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final left = next.difference(DateTime.now());
    final seconds = max(0, left.inSeconds);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

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
          Text(
            _skipped.isEmpty
                ? 'Nghỉ một chút. Những từ chưa nhớ sẽ trở lại khi đến hạn.'
                : 'Còn ${_skipped.length} thẻ đã bỏ qua, chưa đánh giá.',
            textAlign: TextAlign.center,
          ),
          if (_waiting.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_waiting.length} thẻ sẽ quay lại sau ${_countdown()}. '
              'Cứ để trang này mở.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.of(context).muted),
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              if (_last != null)
                OutlinedButton.icon(
                  onPressed: _saving ? null : _undo,
                  icon: const Icon(Icons.undo),
                  label: const Text('Hoàn tác lượt cuối'),
                ),
              if (_skipped.isNotEmpty)
                FilledButton(
                  onPressed: () => setState(() {
                    _show(_skipped.first);
                    _direction = 1;
                  }),
                  child: Text('Học ${_skipped.length} thẻ đã bỏ qua'),
                ),
              if (cards.isNotEmpty) ...[
                OutlinedButton(
                  onPressed: () {
                    _index = cards.length;
                    _go(-1);
                  },
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
