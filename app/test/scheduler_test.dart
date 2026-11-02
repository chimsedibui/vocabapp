import 'package:flutter_test/flutter_test.dart';
import 'package:vocabapp/domain/scheduler.dart';

void main() {
  final scheduler = Scheduler();
  final now = DateTime.utc(2026, 10, 19, 12);
  Schedule review(String state, int interval, Rating rating) =>
      scheduler.review(
        state: state,
        intervalDays: interval,
        lapses: 2,
        rating: rating,
        now: now,
      );

  test('new cards: short steps, then 1 day / 3 days', () {
    const waits = {
      Rating.again: Duration(minutes: 1),
      Rating.hard: Duration(minutes: 10),
      Rating.okay: Duration(hours: 1),
      Rating.good: Duration(days: 1),
      Rating.easy: Duration(days: 3),
    };
    for (final MapEntry(key: rating, value: wait) in waits.entries) {
      final result = review('new', 1, rating);
      expect(result.due, now.add(wait), reason: rating.name);
      expect(result.lapses, 2, reason: 'learning cards never lapse');
      expect(
        result.state,
        wait < const Duration(days: 1) ? 'relearning' : 'review',
      );
    }
  });

  test('review buttons are always strictly increasing', () {
    for (final interval in [1, 2, 3, 5, 10, 40, 200]) {
      final days = [
        for (final r in [Rating.okay, Rating.good, Rating.easy])
          review('review', interval, r).intervalDays,
      ];
      expect(days[0], lessThan(days[1]), reason: 'I=$interval $days');
      expect(days[1], lessThanOrEqualTo(days[2]), reason: 'I=$interval $days');
      if (days[2] < Scheduler.maxDays) {
        expect(days[1], lessThan(days[2]), reason: 'I=$interval $days');
      }
    }
    expect(review('review', 1, Rating.okay).intervalDays, 2);
    expect(review('review', 1, Rating.good).intervalDays, 3);
    expect(review('review', 1, Rating.easy).intervalDays, 4);
    expect(review('review', 10, Rating.okay).intervalDays, 12);
    expect(review('review', 10, Rating.good).intervalDays, 20);
    expect(review('review', 10, Rating.easy).intervalDays, 30);
    expect(review('review', 200, Rating.easy).intervalDays, 365);
  });

  test('forgetting a review card resets it and counts a lapse', () {
    final failed = review('review', 90, Rating.again);
    expect(failed.state, 'relearning');
    expect(failed.due, now.add(const Duration(minutes: 1)));
    expect(failed.intervalDays, 1);
    expect(failed.lapses, 3);
    expect(review('relearning', 1, Rating.good).intervalDays, 1);
  });

  test('hard on a review card checks again in 1 hour, then keeps I', () {
    final hard = review('review', 10, Rating.hard);
    expect(hard.state, 'relearning');
    expect(hard.due, now.add(const Duration(hours: 1)));
    expect(hard.lapses, 2);
    final back = review(hard.state, hard.intervalDays, Rating.good);
    expect(back.intervalDays, 10);
    expect(review(hard.state, hard.intervalDays, Rating.easy).intervalDays, 20);
  });
}
