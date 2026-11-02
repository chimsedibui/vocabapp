import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocabapp/data/database.dart';
import 'package:vocabapp/data/library_repository.dart';
import 'package:vocabapp/domain/models.dart';
import 'package:vocabapp/domain/scheduler.dart';

void main() {
  tz.initializeTimeZones();
  late Database db;
  late LibraryRepository repo;
  late String deck;
  late DateTime now;
  setUp(() async {
    now = DateTime.utc(2026, 10, 19, 16, 59);
    db = await openVocabularyDatabase(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    repo = LibraryRepository(db, clock: () => now);
    deck = (await repo.decks()).single.id;
  });
  tearDown(() async => db.close());

  Future<void> add(
    String term, {
    String key = 'primary',
    String meaning = 'nghĩa',
  }) => repo
      .addWord(term: term, meaning: meaning, deckId: deck, senseKey: key)
      .then((_) {});

  test(
    'part of speech and IPA are stored, shown and kept unless edited',
    () async {
      await repo.addWord(
        term: 'persistent',
        meaning: 'dai dẳng',
        deckId: deck,
        partOfSpeech: 'adjective',
        pronunciation: ' /pəˈsɪstənt/ ',
      );
      var word = (await repo.vocabulary()).single;
      expect(word.partOfSpeech, 'adjective');
      expect(word.pronunciation, 'pəˈsɪstənt');
      expect((await repo.studyQueue()).single.pronunciation, 'pəˈsɪstənt');
      await repo.saveMeaning(word.senseId, 'bền bỉ', approve: true);
      word = (await repo.vocabulary()).single;
      expect(word.partOfSpeech, 'adjective');
      await repo.saveMeaning(
        word.senseId,
        'bền bỉ',
        approve: true,
        details: (partOfSpeech: null, pronunciation: '[pɚˈsɪstənt]'),
      );
      word = (await repo.vocabulary()).single;
      expect(word.partOfSpeech, isNull);
      expect(word.pronunciation, 'pɚˈsɪstənt');
      expect(
        () => repo.addWord(
          term: 'x',
          meaning: 'y',
          deckId: deck,
          partOfSpeech: 'adj',
        ),
        throwsA(isA<UserFacingException>()),
      );
    },
  );
  test('multi-sense / multi-deck does not duplicate cards, Unicode NFC keeps identity', () async {
    await add('bank', key: 'financial', meaning: 'ngân hàng');
    await add('bank', key: 'river', meaning: 'bờ sông');
    final second = await repo.createDeck('Công việc');
    await repo.addWord(
      term: ' bank ',
      meaning: 'ngân hàng',
      deckId: second,
      senseKey: 'financial',
    );
    expect((await repo.stats()).entries, 1);
    expect((await repo.stats()).senses, 2);
    expect((await repo.studyQueue()).length, 2);
    expect((await repo.studyQueue(deckId: second)).length, 2);
    await add('café');
    await add('cafe\u0301');
    expect((await repo.stats()).entries, 2);
    await add('US');
    await add('us');
    expect((await repo.stats()).entries, 4);
  });

  test(
    'conflicting addition rolls back; removing membership preserves history',
    () async {
      await add('retain');
      final card = (await repo.studyQueue()).single;
      await repo.review(card, Rating.good, 'event-1');
      final other = await repo.createDeck('Khác');
      await repo.addWord(
        term: 'retain',
        meaning: 'tài chính',
        deckId: deck,
        senseKey: 'finance',
      );
      await expectLater(
        repo.addWord(
          term: 'retain',
          meaning: 'conflicting',
          deckId: other,
          senseKey: 'finance',
        ),
        throwsA(isA<UserFacingException>()),
      );
      expect((await repo.vocabulary(deckId: other)), isEmpty);
      final word = (await repo.vocabulary()).first;
      await repo.removeFromDeck(word.entryId, deck);
      expect((await repo.vocabulary()).length, 2);
      expect((await db.query('review_events')).length, 1);
      expect((await db.query('cards', where: "state='review'")).length, 1);
    },
  );

  test('same word is reused across case and near-identical meanings', () async {
    expect(
      await repo.addWord(term: 'Tea', meaning: 'Trà.', deckId: deck),
      true,
    );
    expect(
      await repo.addWord(term: 'tea', meaning: 'trà', deckId: deck),
      false,
    );
    expect(
      await repo.addWord(term: 'tea', meaning: 'bữa trà chiều', deckId: deck),
      true,
    );
    expect((await db.query('entries')).length, 1);
    expect(
      (await db.query('senses')).map((r) => r['sense_key']),
      unorderedEquals(['primary', 'primary-2']),
    );
    await repo.addWord(term: 'US', meaning: 'nước Mỹ', deckId: deck);
    await repo.addWord(term: 'us', meaning: 'chúng tôi', deckId: deck);
    expect((await db.query('entries')).length, 3);
    expect((await repo.matches('us')).map((v) => v.term).toSet(), {'US', 'us'});
  });

  test(
    'bulk draft all-or-nothing, duplicates skipped, approval required',
    () async {
      expect(await repo.addDraftLines('retain\nretain\nresilient', deck), 2);
      expect(await repo.studyQueue(), isEmpty);
      expect((await repo.stats()).drafts, 2);
      await expectLater(
        repo.addDraftLines('valid\n${'x' * 201}', deck),
        throwsA(isA<UserFacingException>()),
      );
      expect((await repo.stats()).entries, 2);
      final word = (await repo.vocabulary()).first;
      await expectLater(
        repo.saveMeaning(word.senseId, '', approve: true),
        throwsA(isA<UserFacingException>()),
      );
      await repo.saveMeaning(word.senseId, 'kiên cường', approve: true);
      expect((await repo.studyQueue()).length, 1);
    },
  );

  test('review retries are idempotent and stale snapshots cannot overwrite schedule', () async {
    await add('retain');
    final card = (await repo.studyQueue()).single;
    await repo.review(card, Rating.again, 'same-event');
    await repo.review(card, Rating.again, 'same-event');
    expect((await db.query('review_events')).length, 1);
    // A card still being learned does not lapse.
    expect((await db.query('cards')).single['lapses'], 0);
    await expectLater(
      repo.review(card, Rating.easy, 'another-event'),
      throwsA(isA<UserFacingException>()),
    );
    expect(await repo.studyQueue(), isEmpty);
    now = now.add(const Duration(minutes: 10));
    expect((await repo.studyQueue()).length, 1);
  });

  test(
    'review transaction failure leaves neither event nor changed schedule',
    () async {
      await add('retain');
      final card = (await repo.studyQueue()).single;
      await db.execute(
        "CREATE TRIGGER fail_schedule BEFORE UPDATE ON cards BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(
        repo.review(card, Rating.good, 'event'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('review_events'), isEmpty);
      expect((await db.query('cards')).single['state'], 'new');
    },
  );

  test('new cards have no daily cap', () async {
    for (var i = 0; i < 25; i++) {
      await add('word$i');
    }
    var studied = 0;
    for (var round = 0; round < 3; round++) {
      final queue = await repo.studyQueue();
      for (final card in queue) {
        await repo.review(card, Rating.good, 'event-$round-${card.id}');
        studied++;
      }
    }
    expect(studied, 25);
    expect((await repo.stats()).fresh, 0);
  });

  test(
    'due cards precede fresh cards; search treats SQL wildcards literally',
    () async {
      await add('old');
      var card = (await repo.studyQueue()).single;
      await repo.review(card, Rating.again, 'old-event');
      await add('100%');
      await add('underscore_name');
      now = now.add(const Duration(minutes: 10));
      expect((await repo.studyQueue()).first.id, card.id);
      expect((await repo.vocabulary(search: '%')).single.term, '100%');
      expect(
        (await repo.vocabulary(search: '_')).single.term,
        'underscore_name',
      );
    },
  );

  test(
    'editing keeps due unless reset requested and invalidates open review',
    () async {
      await add('retain');
      final before = (await repo.studyQueue()).single;
      final word = (await repo.vocabulary()).single;
      await repo.saveMeaning(word.senseId, 'giữ lại', approve: true);
      await expectLater(
        repo.review(before, Rating.good, 'stale'),
        throwsA(isA<UserFacingException>()),
      );
      await repo.review((await repo.studyQueue()).single, Rating.good, 'new');
      final due = (await db.query('cards')).single['due_at'];
      await repo.saveMeaning(word.senseId, 'giữ lại; giữ được', approve: true);
      expect((await db.query('cards')).single['due_at'], due);
      await repo.saveMeaning(
        word.senseId,
        'giữ lại',
        approve: true,
        resetSchedule: true,
      );
      expect((await db.query('cards')).single['state'], 'new');
      expect((await db.query('review_events')).length, 1);
    },
  );

  test('suspend excludes cards while archive only hides a deck', () async {
    await add('retain');
    final word = (await repo.vocabulary()).single;
    await repo.archiveDeck(deck);
    expect(await repo.decks(), isEmpty);
    expect((await repo.studyQueue()).length, 1);
    await repo.setSuspended(word.senseId, true);
    expect(await repo.studyQueue(), isEmpty);
    await repo.setSuspended(word.senseId, false);
    expect((await repo.studyQueue()).length, 1);
  });

  test(
    'reopening a real database preserves reviews, identity and due time',
    () async {
      final dir = await Directory.systemTemp.createTemp('vocabapp-db-');
      final path = p.join(dir.path, 'library.db');
      final disk = await openVocabularyDatabase(
        databaseFactoryFfiNoIsolate,
        path,
      );
      final first = LibraryRepository(disk, clock: () => now);
      await first.addWord(
        term: 'retain',
        meaning: 'giữ lại',
        deckId: (await first.decks()).single.id,
      );
      final card = (await first.studyQueue()).single;
      await first.review(card, Rating.good, 'persisted');
      await disk.close();
      final reopened = await openVocabularyDatabase(
        databaseFactoryFfiNoIsolate,
        path,
      );
      expect((await reopened.query('review_events')).single['id'], 'persisted');
      expect((await reopened.query('cards')).single['id'], card.id);
      expect(
        (await reopened.query('cards')).single['due_at'],
        now.add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );

  test(
    'undo restores the card and drops the event; a later change blocks it',
    () async {
      await add('retain');
      final card = (await repo.studyQueue()).single;
      await repo.review(card, Rating.good, 'e1');
      final back = await repo.undoReview(card, 'e1');
      expect(await db.query('review_events'), isEmpty);
      final row = (await db.query('cards')).single;
      expect(row['state'], 'new');
      expect(row['due_at'], isNull);
      expect(row['last_review_id'], isNull);
      expect(back.revision, row['revision']);
      await repo.review(back, Rating.again, 'e2');
      await expectLater(
        repo.undoReview(card, 'e2'),
        throwsA(isA<UserFacingException>()),
      );
    },
  );

  test(
    'deleting the last meaning removes the word, card and history',
    () async {
      await add('retain', key: 'a');
      await add('retain', key: 'b', meaning: 'giữ');
      await repo.review((await repo.studyQueue()).first, Rating.good, 'e1');
      final senses = await repo.vocabulary();
      expect(senses, hasLength(2));
      for (final sense in senses) {
        await repo.deleteSense(sense.senseId);
      }
      for (final table in [
        'entries',
        'senses',
        'cards',
        'review_events',
        'deck_entries',
      ]) {
        expect(await db.query(table), isEmpty, reason: table);
      }
    },
  );

  test('stats: stages, streak and last week', () async {
    await add('a');
    await add('b');
    final queue = await repo.studyQueue();
    await repo.review(queue[0], Rating.good, 'd0');
    now = now.add(const Duration(days: 1));
    await repo.review(queue[1], Rating.again, 'd1');
    final s = await repo.stats();
    expect((s.fresh, s.learning, s.mature), (0, 1, 1));
    expect(s.streak, 2);
    expect(s.lastWeek, [0, 0, 0, 0, 0, 1, 1]);
    now = now.add(const Duration(days: 1));
    expect((await repo.stats()).streak, 2, reason: 'today not studied yet');
    now = now.add(const Duration(days: 1));
    expect((await repo.stats()).streak, 0);
  });
}
