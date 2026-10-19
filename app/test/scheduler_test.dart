import 'package:flutter_test/flutter_test.dart';
import 'package:vocabapp/domain/scheduler.dart';

void main() {
  final scheduler = Scheduler();
  final now = DateTime.utc(2026, 10, 19, 12);
  test('new cards: again 10m, hard/good 1d, easy 4d', () {
    for (final rating in Rating.values) {
      final result = scheduler.review(
        state: 'new',
        intervalDays: 1,
        lapses: 0,
        rating: rating,
        now: now,
      );
      final duration = rating == Rating.again
          ? const Duration(minutes: 10)
          : Duration(days: rating == Rating.easy ? 4 : 1);
      expect(result.due, now.add(duration));
      expect(result.lapses, rating == Rating.again ? 1 : 0);
    }
  });
  test('again resets interval; long review intervals are capped', () {
    final failed = scheduler.review(
      state: 'review',
      intervalDays: 90,
      lapses: 2,
      rating: Rating.again,
      now: now,
    );
    expect(failed.intervalDays, 1);
    expect(failed.state, 'relearning');
    expect(failed.lapses, 3);
    final easy = scheduler.review(
      state: 'review',
      intervalDays: 200,
      lapses: 2,
      rating: Rating.easy,
      now: now,
    );
    expect(easy.intervalDays, 365);
    final hard = scheduler.review(
      state: 'review',
      intervalDays: 7,
      lapses: 0,
      rating: Rating.hard,
      now: now,
    );
    expect(hard.intervalDays, 9);
  });
}
