import 'dart:math';

import 'scheduler.dart';

/// Learning analytics computed from `review_events` (docs/15). Pure Dart so
/// the formulas are testable without SQLite.

/// Again = 1 … Easy = 5.
int ratingScore(Rating r) => r.index + 1;

Rating? ratingByName(String name) =>
    Rating.values.where((r) => r.name == name).firstOrNull;

/// One review as analytics needs it. Times are UTC; [day] is the local study
/// day at midnight UTC.
class ReviewRecord {
  const ReviewRecord({
    required this.cardId,
    required this.rating,
    required this.reviewedAt,
    required this.day,
    required this.wasNew,
    required this.previousState,
    required this.newState,
    required this.previousInterval,
    this.localHour = 12,
    this.previousDue,
    this.sessionId,
    this.shownAt,
    this.flippedAt,
  });
  final String cardId;
  final Rating rating;
  final DateTime reviewedAt, day;
  final bool wasNew;
  final String previousState, newState;
  final int previousInterval;

  /// Local hour (0–23) of the review.
  final int localHour;

  /// When the card was due before this review; null for new cards.
  final DateTime? previousDue;
  final String? sessionId;
  final DateTime? shownAt, flippedAt;

  bool get passed => rating != Rating.again;

  /// A real memory check: the card had left the short steps.
  bool get isRecall => previousState == 'review';

  /// First time the card reached day intervals.
  bool get graduates => newState == 'review' && previousState != 'review';

  /// Time on the card, capped at [LearningReport.maxCardTime] so a card left
  /// open does not count as study. Zero before DB v6 (no [shownAt]).
  Duration get activeTime {
    final shown = shownAt;
    if (shown == null) return Duration.zero;
    final spent = reviewedAt.difference(shown);
    if (spent.isNegative) return Duration.zero;
    return spent > LearningReport.maxCardTime
        ? LearningReport.maxCardTime
        : spent;
  }

  /// Whole days reviewed after the due time (0 when on time or early).
  int get daysLate {
    final due = previousDue;
    if (due == null || !reviewedAt.isAfter(due)) return 0;
    return reviewedAt.difference(due).inDays;
  }

  /// Front shown → answer revealed.
  Duration? get thinkTime => shownAt == null || flippedAt == null
      ? null
      : flippedAt!.difference(shownAt!);
}

class CardRecord {
  const CardRecord({
    required this.term,
    required this.meaning,
    required this.state,
    required this.intervalDays,
    required this.lapses,
    required this.suspended,
    this.dueDay,
  });
  final String term, meaning, state;
  final int intervalDays, lapses;
  final bool suspended;

  /// Local study day the card is due, midnight UTC; null for new cards.
  final DateTime? dueDay;
}

class WeekStat {
  WeekStat(this.start);
  final DateTime start;
  int get reviews => _reviews;
  int get newCards => _newCards;
  int get graduated => _graduated;
  double get minutes => _activeMs / 60000;

  /// Mean rating score (1–5), null without reviews.
  double? get averageScore => _reviews == 0 ? null : _scoreSum / _reviews;

  int _reviews = 0, _newCards = 0, _graduated = 0, _scoreSum = 0, _activeMs = 0;
}

class PassRate {
  PassRate(this.label);
  final String label;
  int checks = 0, passed = 0;
  double? get rate => checks == 0 ? null : passed / checks;
}

class SessionStat {
  SessionStat(this.id, this.start);
  final String id;
  DateTime start;
  int cards = 0, passed = 0;
  Duration active = Duration.zero;
}

/// Sessions whose active time falls in one length bucket.
class SessionLength {
  SessionLength(this.label);
  final String label;
  int sessions = 0, cards = 0, passed = 0;
  double? get rate => cards == 0 ? null : passed / cards;
}

class Trend {
  int up = 0, same = 0, down = 0;
  int get total => up + same + down;
}

class Leech {
  const Leech(this.term, this.meaning, this.lapses, this.again, this.recent);
  final String term, meaning;
  final int lapses, again;

  /// Last ratings, oldest first.
  final List<Rating> recent;
}

class LearningReport {
  LearningReport._();

  static const maxCardTime = Duration(minutes: 2);
  static const weeksShown = 8;
  static const forecastDays = 14;
  static const matureDays = 21;
  static const dailyDays = 14;

  /// Session active time in minutes, [start, end).
  static const lengthBuckets = [(0, 10), (10, 20), (20, 30), (30, 45)];

  /// A length bucket needs this many sessions before it feeds a suggestion.
  static const minSessions = 3;

  /// Interval buckets (days before the check) for recall rate.
  static const intervalBuckets = [(1, 3), (4, 10), (11, 30), (31, 9999)];

  /// Local hours (start inclusive, end exclusive) per part of the day.
  static const dayParts = [
    ('Sáng', 5, 11),
    ('Trưa', 11, 14),
    ('Chiều', 14, 18),
    ('Tối', 18, 22),
    ('Khuya', 22, 5),
  ];

  /// Days late for a recall check.
  static const lateBuckets = [
    ('Đúng hạn', 0, 1),
    ('Trễ 2–7', 2, 7),
    ('Trễ >7', 8, 99999),
  ];

  /// Minimum checks before a rate is trusted for a suggestion.
  static const minChecks = 15;

  /// Card position within a session, for the fatigue curve.
  static const positionBuckets = [(1, 10), (11, 20), (21, 30), (31, 40)];

  /// Oldest first, ending with the current week (Monday start).
  late final List<WeekStat> weeks;

  /// Recall checks of the last 90 days by interval.
  late final List<PassRate> recallByInterval;

  /// All recall checks in the last 30 days.
  late final PassRate recall30;

  /// Not-“again” rate of the last 90 days by part of the day.
  late final List<PassRate> byDayPart;

  /// Recall checks of the last 90 days by how late they were done.
  late final List<PassRate> byLateness;

  /// Plain-language advice derived from the numbers above.
  late final List<String> suggestions;

  /// Pass rate by card position within a session (DB v6 sessions only).
  late final List<PassRate> fatigue;

  /// Newest first, at most 10.
  late final List<SessionStat> sessions;

  /// Active minutes per study day, oldest first, ending today.
  late final List<double> dailyMinutes;

  /// Sessions of the last 90 days by active time; the last bucket is open.
  late final List<SessionLength> sessionLengths;

  /// Mean active minutes per session over the last 90 days, null without
  /// sessions.
  late final double? averageSessionMinutes;

  /// Words reviewed at least twice in the window: last rating vs first.
  late final Trend trend7, trend30;

  late final List<Leech> leeches;

  /// Due reviews per day starting today; overdue cards count for today.
  late final List<int> dueForecast;

  late final int graduatedTotal, matureTotal, studyDays30;

  /// Median front → flip time in the last 30 days.
  late final Duration? medianThink;

  /// Words graduated per week, averaged over the last 4 weeks.
  late final double pace;

  int get totalReviews => _total;
  int _total = 0;

  static DateTime weekStart(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day - (day.weekday - 1));

  factory LearningReport.compute({
    required List<ReviewRecord> reviews,
    required Map<String, CardRecord> cards,
    required DateTime today,
  }) {
    final report = LearningReport._().._total = reviews.length;
    final sorted = [...reviews]
      ..sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));
    DateTime daysAgo(int n) =>
        DateTime.utc(today.year, today.month, today.day - n);

    final thisWeek = weekStart(today);
    final weeks = [
      for (var i = weeksShown - 1; i >= 0; i--)
        WeekStat(
          DateTime.utc(thisWeek.year, thisWeek.month, thisWeek.day - 7 * i),
        ),
    ];
    final byWeek = {for (final w in weeks) w.start: w};

    final recall = [
      for (final (lo, hi) in intervalBuckets)
        PassRate(hi > 999 ? '>${lo - 1} ngày' : '$lo–$hi ngày'),
    ];
    final recall30 = PassRate('30 ngày');
    final fatigue = [
      for (final (lo, hi) in positionBuckets) PassRate('$lo–$hi'),
      PassRate('>${positionBuckets.last.$2}'),
    ];
    final partRates = [for (final (label, _, _) in dayParts) PassRate(label)];
    final lateRates = [
      for (final (label, _, _) in lateBuckets) PassRate(label),
    ];
    final sessions = <String, SessionStat>{};
    final dailyMs = List.filled(dailyDays, 0);
    final positions = <String, int>{};
    final graduated = <String>{};
    final thinks = <int>[];
    final studied = <DateTime>{};
    final byCard = <String, List<ReviewRecord>>{};

    for (final r in sorted) {
      byCard.putIfAbsent(r.cardId, () => []).add(r);
      final week = byWeek[weekStart(r.day)];
      final firstGraduation = r.graduates && graduated.add(r.cardId);
      if (week != null) {
        week._reviews++;
        week._scoreSum += ratingScore(r.rating);
        week._activeMs += r.activeTime.inMilliseconds;
        if (r.wasNew) week._newCards++;
        if (firstGraduation) week._graduated++;
      }
      final age = today.difference(r.day).inDays;
      if (age >= 0 && age < dailyDays) {
        dailyMs[dailyDays - 1 - age] += r.activeTime.inMilliseconds;
      }
      if (age < 30) studied.add(r.day);
      if (age < 90) {
        final part = dayParts.indexWhere(
          (p) => p.$2 < p.$3
              ? r.localHour >= p.$2 && r.localHour < p.$3
              : r.localHour >= p.$2 || r.localHour < p.$3,
        );
        _count(partRates[part], r.passed);
      }
      if (r.isRecall && age < 90) {
        _count(
          lateRates[lateBuckets.indexWhere(
            (b) => r.daysLate <= b.$3 && (r.daysLate >= b.$2 || b.$2 == 0),
          )],
          r.passed,
        );
        final i = intervalBuckets.indexWhere(
          (b) => r.previousInterval >= b.$1 && r.previousInterval <= b.$2,
        );
        if (i >= 0) _count(recall[i], r.passed);
        if (age < 30) _count(recall30, r.passed);
      }
      if (r.thinkTime case final t? when age < 30 && !t.isNegative) {
        thinks.add(t.inMilliseconds);
      }
      if (r.sessionId case final id?) {
        final position = positions[id] = (positions[id] ?? 0) + 1;
        final i = positionBuckets.indexWhere(
          (b) => position >= b.$1 && position <= b.$2,
        );
        _count(fatigue[i < 0 ? fatigue.length - 1 : i], r.passed);
        final start = r.shownAt ?? r.reviewedAt;
        final s = sessions.putIfAbsent(id, () => SessionStat(id, start));
        if (start.isBefore(s.start)) s.start = start;
        s.cards++;
        if (r.passed) s.passed++;
        s.active += r.activeTime;
      }
    }

    Trend trend(int days) {
      final t = Trend();
      final since = daysAgo(days - 1);
      for (final events in byCard.values) {
        final window = events.where((e) => !e.day.isBefore(since)).toList();
        if (window.length < 2) continue;
        final change =
            ratingScore(window.last.rating) - ratingScore(window.first.rating);
        if (change > 0) {
          t.up++;
        } else if (change < 0) {
          t.down++;
        } else {
          t.same++;
        }
      }
      return t;
    }

    final leeches = <Leech>[];
    for (final MapEntry(key: id, value: events) in byCard.entries) {
      final card = cards[id];
      if (card == null || card.suspended) continue;
      final again = events.where((e) => e.rating == Rating.again).length;
      if (card.lapses >= 3 || again >= 4) {
        leeches.add(
          Leech(card.term, card.meaning, card.lapses, again, [
            for (final e in events.skip(max(0, events.length - 8))) e.rating,
          ]),
        );
      }
    }
    leeches.sort(
      (a, b) => b.again != a.again
          ? b.again.compareTo(a.again)
          : b.lapses.compareTo(a.lapses),
    );

    final forecast = List.filled(forecastDays, 0);
    for (final c in cards.values) {
      final due = c.dueDay;
      if (c.suspended || c.state == 'new' || due == null) continue;
      final offset = max(0, due.difference(today).inDays);
      if (offset < forecastDays) forecast[offset]++;
    }

    thinks.sort();
    final recent = weeks.skip(weeksShown - 4);
    final lengths = [
      for (final (lo, hi) in lengthBuckets)
        SessionLength(lo == 0 ? '<$hi phút' : '$lo–$hi phút'),
      SessionLength('>${lengthBuckets.last.$2} phút'),
    ];
    final since = daysAgo(89);
    var activeSum = Duration.zero, counted = 0;
    for (final s in sessions.values) {
      if (s.start.isBefore(since) || s.active == Duration.zero) continue;
      final minutes = s.active.inSeconds / 60;
      final i = lengthBuckets.indexWhere(
        (b) => minutes >= b.$1 && minutes < b.$2,
      );
      final bucket = lengths[i < 0 ? lengths.length - 1 : i];
      bucket.sessions++;
      bucket.cards += s.cards;
      bucket.passed += s.passed;
      activeSum += s.active;
      counted++;
    }
    report
      ..dailyMinutes = [for (final ms in dailyMs) ms / 60000]
      ..sessionLengths = lengths
      ..averageSessionMinutes = counted == 0
          ? null
          : activeSum.inSeconds / 60 / counted
      ..byDayPart = partRates
      ..byLateness = lateRates;
    return report
      ..weeks = weeks
      ..recallByInterval = recall
      ..recall30 = recall30
      ..fatigue = fatigue
      ..sessions =
          (sessions.values.toList()..sort((a, b) => b.start.compareTo(a.start)))
              .take(10)
              .toList()
      ..trend7 = trend(7)
      ..trend30 = trend(30)
      ..leeches = leeches.take(10).toList()
      ..dueForecast = forecast
      ..graduatedTotal = graduated.where(cards.containsKey).length
      ..matureTotal = cards.values
          .where(
            (c) =>
                !c.suspended &&
                c.state == 'review' &&
                c.intervalDays >= matureDays,
          )
          .length
      ..studyDays30 = studied.length
      ..medianThink = thinks.isEmpty
          ? null
          : Duration(milliseconds: thinks[thinks.length ~/ 2])
      ..pace = recent.fold(0, (sum, w) => sum + w.graduated) / 4
      .._suggest();
  }

  void _suggest() {
    String pct(double v) => '${(v * 100).round()}%';
    bool enough(PassRate p) => p.checks >= minChecks;
    final tips = <String>[];

    if (recall30.checks >= minChecks) {
      final rate = recall30.rate!;
      if (rate < 0.8) {
        tips.add(
          'Tỉ lệ nhớ 30 ngày là ${pct(rate)}, dưới mức 85–90%. Giảm số từ mới '
          'mỗi phiên và chấm “Khó” khi phải nghĩ lâu để thẻ quay lại sớm hơn.',
        );
      } else if (rate > 0.95) {
        tips.add(
          'Tỉ lệ nhớ 30 ngày là ${pct(rate)}: trí nhớ đang dư sức. '
          'Có thể thêm từ mới mỗi phiên hoặc chấm “Dễ” mạnh tay hơn.',
        );
      }
    }

    final first = fatigue.first;
    if (enough(first)) {
      for (final (i, p) in fatigue.indexed.skip(1)) {
        if (enough(p) && first.rate! - p.rate! >= 0.1) {
          tips.add(
            'Từ thẻ thứ ${p.label.split('–').first.replaceAll('>', '')} trở đi '
            'bạn nhớ kém hơn đầu phiên ${pct(first.rate! - p.rate!)} '
            '(${pct(first.rate!)} → ${pct(p.rate!)}). Thử chia thành phiên '
            'khoảng ${positionBuckets[i - 1].$2} thẻ, nghỉ ngắn rồi học tiếp.',
          );
          break;
        }
      }
    }

    final lengths =
        sessionLengths
            .where((l) => l.sessions >= minSessions && l.cards >= minChecks)
            .toList()
          ..sort((a, b) => b.rate!.compareTo(a.rate!));
    if (lengths.length >= 2 &&
        lengths.first.rate! - lengths.last.rate! >= 0.1) {
      tips.add(
        'Phiên ${lengths.first.label} cho tỉ lệ nhớ cao nhất '
        '(${pct(lengths.first.rate!)}), phiên ${lengths.last.label} thấp nhất '
        '(${pct(lengths.last.rate!)}). Ưu tiên học theo phiên '
        '${lengths.first.label}.',
      );
    }

    final parts = byDayPart.where(enough).toList()
      ..sort((a, b) => b.rate!.compareTo(a.rate!));
    if (parts.length >= 2 && parts.first.rate! - parts.last.rate! >= 0.1) {
      tips.add(
        'Bạn nhớ tốt nhất vào buổi ${parts.first.label.toLowerCase()} '
        '(${pct(parts.first.rate!)}), kém nhất buổi '
        '${parts.last.label.toLowerCase()} (${pct(parts.last.rate!)}). '
        'Ưu tiên học từ mới vào buổi ${parts.first.label.toLowerCase()}.',
      );
    }

    final onTime = byLateness.first;
    final late = byLateness.skip(1).where(enough).toList();
    if (enough(onTime) && late.isNotEmpty) {
      final worst = late.reduce((a, b) => a.rate! < b.rate! ? a : b);
      if (onTime.rate! - worst.rate! >= 0.1) {
        tips.add(
          'Ôn trễ hạn làm tỉ lệ nhớ giảm từ ${pct(onTime.rate!)} xuống '
          '${pct(worst.rate!)} (${worst.label.toLowerCase()} ngày). '
          'Học đều ít phút mỗi ngày hiệu quả hơn dồn một buổi dài.',
        );
      }
    }

    if (studyDays30 < 15) {
      tips.add(
        'Bạn học $studyDays30/30 ngày gần đây. Đặt một mốc cố định mỗi ngày '
        '(ví dụ 10 phút sau bữa tối) để thẻ không bị dồn.',
      );
    }

    if (dueForecast.first >= 50) {
      tips.add(
        'Hôm nay có ${dueForecast.first} thẻ đến hạn. Ôn hết thẻ cũ trước, '
        'tạm dừng thêm từ mới cho tới khi số thẻ đến hạn giảm.',
      );
    }

    if (trend30.total >= 10 && trend30.down > trend30.up) {
      tips.add(
        'Trong 30 ngày, ${trend30.down} từ bị chấm thấp hơn trước, chỉ '
        '${trend30.up} từ tăng. Có thể đang thêm từ mới nhanh hơn khả năng ôn.',
      );
    }

    if (leeches.length >= 3) {
      tips.add(
        'Có ${leeches.length} từ khó lặp lại. Thêm câu ví dụ hoặc ghi chú '
        'cách nhớ, tách nghĩa dễ nhầm, hoặc tạm dừng bớt để đỡ nản.',
      );
    }

    final think = medianThink;
    if (think != null && think > const Duration(seconds: 8)) {
      tips.add(
        'Bạn thường nghĩ ${think.inSeconds} giây trước khi lật. Nếu sau '
        '5 giây chưa nhớ ra, hãy lật và chấm thật: nghĩ lâu dễ gây mất tập trung.',
      );
    }
    suggestions = tips;
  }

  static void _count(PassRate p, bool passed) {
    p.checks++;
    if (passed) p.passed++;
  }
}
