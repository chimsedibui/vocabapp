import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocabapp/data/analytics_repository.dart';
import 'package:vocabapp/data/database.dart';
import 'package:vocabapp/data/library_repository.dart';
import 'package:vocabapp/domain/analytics.dart';
import 'package:vocabapp/domain/scheduler.dart';

void main() {
  tz.initializeTimeZones();
  final today = DateTime.utc(2026, 11, 10);

  ReviewRecord review(
    String card,
    Rating rating, {
    int daysAgo = 0,
    String previous = 'review',
    String next = 'review',
    int interval = 5,
    String? session,
    int hour = 9,
    int lateDays = 0,
    int secondsShown = 20,
    int minute = 0,
  }) {
    final day = DateTime.utc(today.year, today.month, today.day - daysAgo);
    final at = day.add(Duration(hours: hour, minutes: minute));
    return ReviewRecord(
      cardId: card,
      rating: rating,
      reviewedAt: at,
      day: day,
      wasNew: previous == 'new',
      previousState: previous,
      newState: next,
      previousInterval: interval,
      localHour: hour,
      previousDue: previous == 'new'
          ? null
          : at.subtract(Duration(days: lateDays, hours: 1)),
      sessionId: session,
      shownAt: at.subtract(Duration(seconds: secondsShown)),
      flippedAt: at.subtract(Duration(seconds: secondsShown ~/ 2)),
    );
  }

  CardRecord card(String term, {int lapses = 0, DateTime? due}) => CardRecord(
    term: term,
    meaning: 'nghĩa $term',
    state: due == null ? 'new' : 'review',
    intervalDays: 30,
    lapses: lapses,
    suspended: false,
    dueDay: due,
  );

  test('graduation, weekly minutes and recall by interval', () {
    final r = LearningReport.compute(
      today: today,
      cards: {
        'a': card('a', due: today),
        'b': card('b', due: today),
      },
      reviews: [
        review('a', Rating.good, daysAgo: 1, previous: 'new', next: 'review'),
        review(
          'b',
          Rating.hard,
          daysAgo: 1,
          previous: 'new',
          next: 'relearning',
        ),
        review('b', Rating.good, previous: 'relearning', next: 'review'),
        review('a', Rating.again, interval: 2, next: 'relearning'),
        review('a', Rating.good, previous: 'relearning', next: 'review'),
        review('b', Rating.good, interval: 20, secondsShown: 600),
      ],
    );
    expect(r.graduatedTotal, 2);
    expect(r.weeks.last.graduated, 2);
    expect(r.weeks.last.newCards, 2);
    // 5 cards × 20 s plus one left open, capped at 2 minutes.
    expect(r.weeks.last.minutes, closeTo((5 * 20 + 120) / 60, 1e-9));
    expect(r.recallByInterval[0].checks, 1);
    expect(r.recallByInterval[0].rate, 0);
    expect(r.recallByInterval[2].rate, 1);
    expect(r.recall30.checks, 2);
    expect(r.matureTotal, 2);
    expect(r.dueForecast.first, 2);
  });

  test('rating trend compares last vs first rating in the window', () {
    final r = LearningReport.compute(
      today: today,
      cards: {},
      reviews: [
        review('up', Rating.again, daysAgo: 3),
        review('up', Rating.good),
        review('down', Rating.easy, daysAgo: 20),
        review('down', Rating.hard),
        review('old', Rating.again, daysAgo: 40),
        review('old', Rating.good),
      ],
    );
    expect((r.trend7.up, r.trend7.down, r.trend7.same), (1, 0, 0));
    expect((r.trend30.up, r.trend30.down), (1, 1));
  });

  test('suggestions react to fatigue, day part, lateness and leeches', () {
    final reviews = <ReviewRecord>[];
    for (var s = 0; s < 3; s++) {
      for (var i = 0; i < 25; i++) {
        reviews.add(
          review(
            'c$s-$i',
            // Evening session (s0) also misses odd cards early on.
            (i < 10 && !(s == 0 && i.isOdd)) || i.isEven
                ? Rating.good
                : Rating.again,
            daysAgo: s,
            session: 's$s',
            hour: s == 0 ? 21 : 8,
            lateDays: i >= 10 ? 5 : 0,
            minute: i,
          ),
        );
      }
    }
    final cards = {
      for (final t in ['x', 'y', 'z']) t: card(t, lapses: 3, due: today),
    };
    for (final t in cards.keys) {
      reviews.add(review(t, Rating.again));
    }
    final r = LearningReport.compute(
      today: today,
      cards: cards,
      reviews: reviews,
    );
    expect(r.leeches.map((l) => l.term), unorderedEquals(['x', 'y', 'z']));
    final tips = r.suggestions.join('\n');
    expect(tips, contains('phiên'));
    expect(tips, contains('buổi sáng'));
    expect(tips, contains('trễ hạn'));
    expect(tips, contains('từ khó'));
    expect(tips, contains('3/30 ngày'));
  });

  test('timing is stored per review and exported as CSV', () async {
    final db = await openVocabularyDatabase(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final now = DateTime.utc(2026, 11, 10, 2);
    final repo = LibraryRepository(db, clock: () => now);
    await repo.addWord(
      term: 'quote',
      meaning: 'trích "dẫn", ví dụ',
      deckId: (await repo.decks()).single.id,
    );
    await repo.review(
      (await repo.studyQueue()).single,
      Rating.good,
      'e1',
      sessionId: 's1',
      shownAt: now.subtract(const Duration(seconds: 9)),
      flippedAt: now.subtract(const Duration(seconds: 4)),
    );
    final row = (await db.query('review_events')).single;
    expect(row['session_id'], 's1');
    expect(row['shown_at'], now.millisecondsSinceEpoch - 9000);

    final report = await repo.learningReport();
    expect(report.sessions.single.cards, 1);
    expect(report.sessions.single.active, const Duration(seconds: 9));
    expect(report.medianThink, const Duration(seconds: 5));
    expect(report.byDayPart.first.checks, 1);

    final lines = (await repo.reviewsCsv()).trim().split('\n');
    expect(lines, hasLength(2));
    expect(lines[1], contains('"trích ""dẫn"", ví dụ"'));
    expect(lines[1], contains(',5000,4000,'));
  });
}
