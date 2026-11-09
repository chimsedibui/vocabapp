import 'package:timezone/timezone.dart' as tz;

import '../domain/analytics.dart';
import 'library_repository.dart';

/// Reads review history for the Insights page and the CSV export (docs/15).
extension LearningAnalytics on LibraryRepository {
  static const _reviewsSql = '''SELECT r.*, e.term, s.meaning, c.lapses
    FROM review_events r JOIN cards c ON c.id=r.card_id
    JOIN senses s ON s.id=c.sense_id JOIN entries e ON e.id=s.entry_id
    ORDER BY r.reviewed_at, r.id''';

  Future<LearningReport> learningReport() async {
    final location = tz.getLocation((await settings())['timezone'] as String);
    DateTime localDay(int ms) {
      final t = tz.TZDateTime.fromMillisecondsSinceEpoch(location, ms);
      return DateTime.utc(t.year, t.month, t.day);
    }

    DateTime? time(Object? ms) => ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);

    final rows = await db.rawQuery(_reviewsSql);
    final cardRows = await db.rawQuery(
      '''SELECT c.*, e.term, s.meaning FROM cards c
      JOIN senses s ON s.id=c.sense_id JOIN entries e ON e.id=s.entry_id''',
    );
    return LearningReport.compute(
      today: localDay(clock().toUtc().millisecondsSinceEpoch),
      reviews: [
        for (final r in rows)
          if (ratingByName(r['rating'] as String) case final rating?)
            ReviewRecord(
              cardId: r['card_id'] as String,
              rating: rating,
              reviewedAt: time(r['reviewed_at'])!,
              day: DateTime.parse('${r['study_day']}T00:00:00Z'),
              wasNew: r['was_new'] == 1,
              previousState: r['previous_state'] as String,
              newState: r['new_state'] as String,
              previousInterval: r['previous_interval'] as int,
              localHour: tz.TZDateTime.fromMillisecondsSinceEpoch(
                location,
                r['reviewed_at'] as int,
              ).hour,
              previousDue: time(r['previous_due']),
              sessionId: r['session_id'] as String?,
              shownAt: time(r['shown_at']),
              flippedAt: time(r['flipped_at']),
            ),
      ],
      cards: {
        for (final c in cardRows)
          c['id'] as String: CardRecord(
            term: c['term'] as String,
            meaning: c['meaning'] as String,
            state: c['state'] as String,
            intervalDays: c['interval_days'] as int,
            lapses: c['lapses'] as int,
            suspended: c['suspended'] == 1,
            dueDay: c['due_at'] == null ? null : localDay(c['due_at'] as int),
          ),
      },
    );
  }

  /// Every review, one row each, for analysis outside the app
  /// (`scripts/analytics/analyze.py`). Times are UTC ISO 8601; durations ms.
  Future<String> reviewsCsv() async {
    String iso(Object? ms) => ms == null
        ? ''
        : DateTime.fromMillisecondsSinceEpoch(
            ms as int,
            isUtc: true,
          ).toIso8601String();
    String diff(Object? from, Object? to) =>
        from == null || to == null ? '' : '${(to as int) - (from as int)}';
    const header = [
      'event_id',
      'card_id',
      'term',
      'meaning',
      'rating',
      'score',
      'reviewed_at',
      'study_day',
      'session_id',
      'shown_at',
      'flipped_at',
      'think_ms',
      'answer_ms',
      'was_new',
      'previous_state',
      'new_state',
      'previous_interval',
      'new_interval',
      'card_lapses',
      'scheduler_version',
    ];
    final out = StringBuffer()..writeln(header.join(','));
    for (final r in await db.rawQuery(_reviewsSql)) {
      final rating = ratingByName(r['rating'] as String);
      out.writeln(
        [
          r['id'],
          r['card_id'],
          r['term'],
          r['meaning'],
          r['rating'],
          rating == null ? '' : ratingScore(rating),
          iso(r['reviewed_at']),
          r['study_day'],
          r['session_id'] ?? '',
          iso(r['shown_at']),
          iso(r['flipped_at']),
          diff(r['shown_at'], r['flipped_at']),
          diff(r['flipped_at'] ?? r['shown_at'], r['reviewed_at']),
          r['was_new'],
          r['previous_state'],
          r['new_state'],
          r['previous_interval'],
          r['new_interval'],
          r['lapses'],
          r['scheduler_version'],
        ].map((v) => _csv('$v')).join(','),
      );
    }
    return out.toString();
  }

  static String _csv(String v) =>
      RegExp(r'[",\r\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
}
