import 'dart:math';

enum Rating {
  again('Quên'),
  hard('Khó'),
  okay('Tạm'),
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

/// Scheduler v2, specified in docs/11; intentionally independent of
/// Flutter/SQLite.
///
/// New and `relearning` cards go through short steps (1 min, 10 min, 1 h) so
/// a word comes back several times in one sitting (successive relearning),
/// then graduate to day intervals that grow with each successful review.
/// While relearning, `intervalDays` holds the interval a card returns to.
class Scheduler {
  static const version = 2;
  static const maxDays = 365;

  Schedule review({
    required String state,
    required int intervalDays,
    required int lapses,
    required Rating rating,
    required DateTime now,
  }) {
    final utc = now.toUtc();
    final interval = max(1, intervalDays);
    Schedule soon(Duration wait, {int? keep, int lapse = 0}) =>
        Schedule('relearning', utc.add(wait), keep ?? interval, lapses + lapse);
    Schedule days(int value) {
      final capped = min(value, maxDays);
      return Schedule(
        'review',
        utc.add(Duration(days: capped)),
        capped,
        lapses,
      );
    }

    if (state == 'review') {
      // Each button is strictly longer than the one before it.
      final okay = (interval * 1.2).ceil();
      final good = max(okay + 1, interval * 2);
      return switch (rating) {
        Rating.again => soon(const Duration(minutes: 1), keep: 1, lapse: 1),
        Rating.hard => soon(const Duration(hours: 1)),
        Rating.okay => days(okay),
        Rating.good => days(good),
        Rating.easy => days(max(good + 1, interval * 3)),
      };
    }
    return switch (rating) {
      Rating.again => soon(const Duration(minutes: 1), keep: 1),
      Rating.hard => soon(const Duration(minutes: 10)),
      Rating.okay => soon(const Duration(hours: 1)),
      Rating.good => days(interval),
      Rating.easy => days(max(3, interval * 2)),
    };
  }
}
