import 'dart:math';

enum Rating {
  again('Quên'),
  hard('Khó'),
  good('Nhớ'),
  easy('Dễ');

  const Rating(this.label);
  final String label;
}

class Schedule {
  const Schedule(this.state, this.due, this.intervalDays, this.lapses);
  final String state;
  final DateTime due;
  final int intervalDays, lapses;
}

/// Baseline v1 specified in docs/03; intentionally independent of Flutter/SQLite.
class Scheduler {
  static const version = 1;

  Schedule review({
    required String state,
    required int intervalDays,
    required int lapses,
    required Rating rating,
    required DateTime now,
  }) {
    final utc = now.toUtc();
    if (rating == Rating.again) {
      return Schedule(
        'relearning',
        utc.add(const Duration(minutes: 10)),
        1,
        lapses + 1,
      );
    }
    final previous = max(1, intervalDays);
    final days = state == 'new'
        ? (rating == Rating.easy ? 4 : 1)
        : switch (rating) {
            Rating.hard => max(1, (previous * 1.2).ceil()),
            Rating.good => max(1, previous * 2),
            Rating.easy => max(4, previous * 3),
            Rating.again => throw StateError('Handled above'),
          };
    final capped = min(days, 365);
    return Schedule('review', utc.add(Duration(days: capped)), capped, lapses);
  }
}
