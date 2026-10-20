import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocabapp/data/database.dart';
import 'package:vocabapp/data/ids.dart';
import 'package:vocabapp/data/library_repository.dart';
import 'package:vocabapp/domain/scheduler.dart';
import 'package:vocabapp/services/backup_service.dart';
import 'package:vocabapp/services/sync_service.dart';
import 'package:vocabapp/ui/app.dart';

import 'sync_schema_helper.dart';

/// In-memory twin of server/sync-worker with the same merge rules.
class FakeSyncServer {
  final rows = <String, Map<String, Object?>>{};
  var seq = 0;
  int? failWith;
  String failCode = 'quota';
  int requests = 0;

  late final client = MockClient((request) async {
    requests++;
    if (request.headers['authorization'] != 'Bearer $token') {
      return reply({'error': 'auth'}, 401);
    }
    if (failWith != null) {
      return reply({'error': failCode}, failWith!);
    }
    final url = request.url;
    if (url.path.endsWith('/v1/status')) {
      return reply({'seq': seq});
    }
    if (url.path.endsWith('/v1/pull')) {
      final after = int.parse(url.queryParameters['after']!);
      final device = url.queryParameters['device']!;
      final limit = int.parse(url.queryParameters['limit']!);
      final page =
          (rows.values
                  .where(
                    (r) => (r['s'] as int) > after && r['device'] != device,
                  )
                  .toList()
                ..sort((a, b) => (a['s'] as int).compareTo(b['s'] as int)))
              .take(limit)
              .map(
                (r) => {
                  for (final k in ['t', 'p', 'd', 'x', 'c', 's']) k: r[k],
                },
              )
              .toList();
      final more = page.length == limit;
      return reply({
        'rows': page,
        'cursor': more ? page.last['s'] : (seq > after ? seq : after),
        'more': more,
      });
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final base = seq;
    var accepted = 0;
    for (final (i, r) in (body['rows'] as List).indexed) {
      final key = '${r['t']}|${r['p']}';
      final old = rows[key];
      if (old != null && (old['c'] as int) > (r['c'] as int)) continue;
      rows[key] = {
        ...r as Map<String, dynamic>,
        'device': body['device'],
        's': base + i + 1,
      };
      seq = base + i + 1;
      accepted++;
    }
    return reply({'accepted': accepted});
  });

  static const token = 'test-token-0123456789abcdefghij';
  static const config = SyncConfig(url: 'https://sync.test', token: token);
}

class Device {
  Device(this.db, FakeSyncServer server)
    : repo = LibraryRepository(db),
      sync = SyncService(
        db,
        loadConfig: () async => FakeSyncServer.config,
        client: server.client,
      );
  final Database db;
  final LibraryRepository repo;
  final SyncService sync;

  static Future<Device> open(FakeSyncServer server) async => Device(
    await openVocabularyDatabase(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
      singleInstance: false,
    ),
    server,
  );

  Future<String> deck() async => (await repo.decks()).single.id;
  Future<List<Map<String, Object?>>> table(String t) =>
      db.query(t, orderBy: syncTables[t]!.join(','));
}

http.Response reply(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  tz.initializeTimeZones();
  late FakeSyncServer server;
  late Device a, b;
  setUp(() async {
    server = FakeSyncServer();
    a = await Device.open(server);
    b = await Device.open(server);
  });
  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  Future<void> converge() async {
    await a.sync.runOnce(FakeSyncServer.config);
    await b.sync.runOnce(FakeSyncServer.config);
    await a.sync.runOnce(FakeSyncServer.config);
  }

  Future<void> expectSameLibrary() async {
    for (final t in syncTables.keys) {
      expect(await b.table(t), await a.table(t), reason: t);
    }
    expect(await a.db.query('sync_outbox'), isEmpty);
    expect(await b.db.query('sync_outbox'), isEmpty);
  }

  test('fresh devices share the default group and merge words', () async {
    expect(await a.deck(), await b.deck());
    await a.repo.addWord(
      term: 'retain',
      meaning: 'giữ lại',
      deckId: await a.deck(),
    );
    await b.repo.addWord(
      term: 'bank',
      meaning: 'ngân hàng',
      deckId: await b.deck(),
    );
    await b.repo.addDraftLines('retain\nharbor', await b.deck());
    await converge();
    await expectSameLibrary();
    expect((await b.repo.stats()).senses, 3);
    expect((await a.repo.decks()).single.count, 3);
  });

  test('offline reviews on both devices keep every event', () async {
    await a.repo.addWord(
      term: 'retain',
      meaning: 'giữ lại',
      deckId: await a.deck(),
    );
    await converge();
    await a.repo.review((await a.repo.studyQueue()).single, Rating.good, 'ra');
    await tick();
    await b.repo.review((await b.repo.studyQueue()).single, Rating.again, 'rb');
    await converge();
    await expectSameLibrary();
    expect((await a.db.query('review_events')).map((r) => r['id']), {
      'ra',
      'rb',
    });
    // The later review decides the schedule on both devices.
    expect((await a.db.query('cards')).single['last_review_id'], 'rb');
    expect((await a.repo.stats()).reviewedToday, 2);
  });

  test('last edit wins and an older remote version never overwrites', () async {
    await a.repo.addWord(
      term: 'bank',
      meaning: 'ngân hàng',
      deckId: await a.deck(),
    );
    await converge();
    final sense = (await a.db.query('senses')).single['id'] as String;
    Future<void> edit(Device d, String meaning) => d.db.update(
      'senses',
      {'meaning': meaning, 'search_text': 'bank $meaning'},
      where: 'id=?',
      whereArgs: [sense],
    );
    await edit(a, 'bờ sông');
    await tick();
    await edit(b, 'ngân hàng (tài chính)');
    // b pulls a's older edit first, keeps its own newer one, then pushes it.
    await b.sync.runOnce(FakeSyncServer.config);
    await a.sync.runOnce(FakeSyncServer.config);
    await expectSameLibrary();
    expect(
      (await a.db.query('senses')).single['meaning'],
      'ngân hàng (tài chính)',
    );
  });

  test('deletes replicate as tombstones', () async {
    final second = await a.repo.createDeck('Công việc');
    await a.repo.addWord(term: 'deadline', meaning: 'hạn chót', deckId: second);
    await converge();
    final entry = (await a.db.query('entries')).single['id'] as String;
    await b.repo.removeFromDeck(entry, second);
    await converge();
    await expectSameLibrary();
    expect(await a.db.query('deck_entries'), isEmpty);
  });

  test('quota errors keep the queue and the next sync delivers it', () async {
    await a.repo.addWord(
      term: 'retain',
      meaning: 'giữ lại',
      deckId: await a.deck(),
    );
    server.failWith = 503;
    await a.sync.sync();
    expect(a.sync.lastError, contains('hết hạn mức'));
    expect(a.sync.pending, greaterThan(0));
    expect(server.rows, isEmpty);
    server.failWith = null;
    await a.sync.sync();
    expect(a.sync.lastError, isNull);
    expect(a.sync.pending, 0);
    await b.sync.sync();
    expect(b.sync.remoteVersion, 1);
    expect((await b.repo.stats()).senses, 1);
  });

  test('wrong token is reported without touching data', () async {
    final wrong = SyncService(
      a.db,
      loadConfig: () async => const SyncConfig(
        url: 'https://sync.test',
        token: 'wrong-token-0123456789abcdef',
      ),
      client: server.client,
    );
    await a.repo.addWord(
      term: 'retain',
      meaning: 'giữ lại',
      deckId: await a.deck(),
    );
    await wrong.sync();
    expect(wrong.lastError, contains('Sai mã đồng bộ'));
    expect(wrong.pending, greaterThan(0));
  });

  test('restoring a backup replaces the library on the other device', () async {
    await a.repo.addWord(
      term: 'retain',
      meaning: 'giữ lại',
      deckId: await a.deck(),
    );
    final snapshot = await BackupService(a.db).export();
    await a.repo.addWord(
      term: 'bank',
      meaning: 'ngân hàng',
      deckId: await a.deck(),
    );
    await converge();
    expect((await b.repo.stats()).senses, 2);
    await tick();
    await BackupService(b.db).restore(snapshot, saveRecovery: (_) async {});
    await converge();
    await expectSameLibrary();
    expect((await a.repo.stats()).senses, 1);
  });

  test(
    'upgrade rewrites legacy random IDs and keeps every reference',
    () async {
      final dir = await Directory.systemTemp.createTemp('vocabapp-sync');
      final path = '${dir.path}/db';
      var db = await openVocabularyDatabase(databaseFactoryFfiNoIsolate, path);
      final repo = LibraryRepository(db);
      await repo.addWord(
        term: 'retain',
        meaning: 'giữ lại',
        deckId: (await repo.decks()).single.id,
      );
      await repo.review((await repo.studyQueue()).single, Rating.good, 'ev');
      await dropSyncSchema(db);
      await db.transaction((tx) async {
        await tx.execute('PRAGMA defer_foreign_keys = ON');
        for (final (t, refs) in [
          ('decks', [('deck_entries', 'deck_id')]),
          ('entries', [('senses', 'entry_id'), ('deck_entries', 'entry_id')]),
          ('senses', [('cards', 'sense_id')]),
          ('cards', [('review_events', 'card_id')]),
        ]) {
          final old = (await tx.query(t)).single['id'];
          final legacy = 'legacy-$t';
          await tx.update(t, {'id': legacy}, where: 'id=?', whereArgs: [old]);
          for (final (rt, c) in refs) {
            await tx.update(rt, {c: legacy}, where: '$c=?', whereArgs: [old]);
          }
        }
      });
      await db.setVersion(3);
      await db.close();
      db = await openVocabularyDatabase(databaseFactoryFfiNoIsolate, path);
      try {
        final entry = (await db.query('entries')).single;
        final sense = (await db.query('senses')).single;
        expect(entry['id'], Ids.entry('retain', 'en', 'vi'));
        expect((await db.query('decks')).single['id'], Ids.deck('daily'));
        expect(sense['id'], Ids.sense(entry['id'] as String, 'primary'));
        expect(
          (await db.query('cards')).single['id'],
          Ids.card(sense['id'] as String),
        );
        expect(
          (await db.query('review_events')).single['card_id'],
          Ids.card(sense['id'] as String),
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(await db.query('sync_outbox'), isEmpty);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );

  testWidgets('settings shows sync state and errors without blocking study', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => a.repo.addWord(
        term: 'retain',
        meaning: 'giữ lại',
        deckId: Ids.deck('daily'),
      ),
    );
    server.failWith = 503;
    await tester.runAsync(a.sync.sync);
    await tester.pumpWidget(VocabApp(repository: a.repo, sync: a.sync));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('Học ngay'), findsOneWidget);
    await tester.tap(find.text('Cài đặt').last);
    await tester.pumpAndSettle();
    expect(find.text('Đồng bộ máy tính ↔ điện thoại'), findsOneWidget);
    expect(find.textContaining('hết hạn mức'), findsOneWidget);
    server.failWith = null;
    await tester.runAsync(a.sync.sync);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(find.textContaining('Đồng bộ lúc'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  final liveUrl = Platform.environment['SYNC_TEST_URL'];
  test('live Worker: two devices converge through real D1 SQL', () async {
    final config = SyncConfig(
      url: liveUrl!,
      token: Platform.environment['SYNC_TEST_TOKEN']!,
    );
    Future<SyncService> device(Database db) async =>
        SyncService(db, loadConfig: () async => config);
    final x = await Device.open(server), y = await Device.open(server);
    final sx = await device(x.db), sy = await device(y.db);
    try {
      await x.repo.addWord(
        term: 'live-${DateTime.now().microsecondsSinceEpoch}',
        meaning: 'thử thật',
        deckId: await x.deck(),
      );
      await x.repo.review(
        (await x.repo.studyQueue()).single,
        Rating.good,
        'live-${DateTime.now().microsecondsSinceEpoch}',
      );
      await sx.runOnce(config);
      await sy.runOnce(config);
      for (final t in ['entries', 'senses', 'cards', 'review_events']) {
        final mine = await x.table(t);
        final theirs = await y.table(t);
        expect(theirs, containsAll(mine), reason: t);
      }
    } finally {
      sx.dispose();
      sy.dispose();
      await x.db.close();
      await y.db.close();
    }
  }, skip: liveUrl == null ? 'Set SYNC_TEST_URL/SYNC_TEST_TOKEN' : false);
}
