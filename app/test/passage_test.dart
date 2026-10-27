import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocabapp/data/database.dart';
import 'package:vocabapp/data/library_repository.dart';
import 'package:vocabapp/data/passage_repository.dart';
import 'package:vocabapp/domain/models.dart';
import 'package:vocabapp/domain/passage.dart';
import 'package:vocabapp/domain/scheduler.dart';
import 'package:vocabapp/services/ai_configuration.dart';
import 'package:vocabapp/services/backup_service.dart';
import 'package:vocabapp/services/passage_service.dart';
import 'package:vocabapp/ui/passage_page.dart';

import 'sync_schema_helper.dart';

const config = AiConfiguration(
  provider: AiProvider.openai,
  key: 'test-secret',
  model: 'test-model',
);
const azure = AiConfiguration(
  provider: AiProvider.azure,
  key: 'azure-secret',
  model: 'my-deployment',
  endpoint: 'https://test.openai.azure.com',
);
const item = PassageItem('persistent', 'B2', 'dai dẳng');
final request = PassageRequest(
  'The persistent effort helped retain knowledge.',
);
String output(List<PassageItem> items) =>
    jsonEncode({'items': items.map((e) => e.toJson()).toList()});
http.Response response({
  String? content,
  String finish = 'stop',
  String? refusal,
}) => http.Response(
  jsonEncode({
    'choices': [
      {
        'finish_reason': finish,
        'message': {
          'content': content ?? output([item]),
          'refusal': refusal,
        },
      },
    ],
    'usage': {
      'prompt_tokens': 120,
      'completion_tokens': 35,
      'completion_tokens_details': {'reasoning_tokens': 4},
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  tz.initializeTimeZones();
  test('CEFR threshold, Unicode whitespace, boundaries and duplicates are checked locally', () {
    final r = PassageRequest(
      'The persistent\n effort helped retain knowledge. café',
    );
    final result = validatePassageResult(
      output([
        item,
        item,
        const PassageItem('effort', 'A2', 'nỗ lực'),
        const PassageItem('he', 'B1', 'anh ấy'),
        const PassageItem('absent', 'C1', 'vắng'),
        const PassageItem('retain knowledge', 'C1', 'giữ kiến thức'),
        const PassageItem('cafe\u0301', 'B1', 'cà phê'),
      ]),
      r,
    );
    expect(result.items.map((i) => i.term), [
      'persistent',
      'retain knowledge',
      'café',
    ]);
    expect(result.removed, 4);
  });
  test('malformed, extra keys, truncated and excess output are errors; empty succeeds', () {
    for (final json in [
      '{"items":',
      '{"items":[],"extra":1}',
      '{"items":[{"term":"x","level":"B1","meaning":""}]}',
    ]) {
      expect(
        () => validatePassageResult(json, request),
        throwsA(isA<UserFacingException>()),
      );
    }
    expect(
      () => validatePassageResult(
        output([item, item]),
        PassageRequest(request.text, maxItems: 1),
      ),
      throwsA(isA<UserFacingException>()),
    );
    expect(validatePassageResult('{"items":[]}', request).items, isEmpty);
  });
  test(
    'budgets reject long input and cache is NFC normalized/settings sensitive',
    () {
      expect(
        () => PassageRequest('a' * 100001),
        throwsA(isA<UserFacingException>()),
      );
      expect(
        () => PassageRequest('a ' * 7000).checkBudget(16384),
        throwsA(isA<UserFacingException>()),
      );
      expect(
        PassageRequest('cafe\u0301\r\n').cacheKey(config.identity),
        PassageRequest('café').cacheKey(config.identity),
      );
      expect(
        request.cacheKey(config.identity),
        isNot(request.cacheKey(azure.identity)),
      );
      expect(
        request.cacheKey(config.identity),
        isNot(
          PassageRequest(
            request.text,
            minLevel: 'C1',
          ).cacheKey(config.identity),
        ),
      );
    },
  );
  test('Azure rejects non-HTTPS, hostile redirects/userinfo and foreign hosts before sending a key', () {
    for (final endpoint in [
      'http://test.openai.azure.com',
      'https://test.openai.azure.com.evil.org',
      'https://test.openai.azure.com?key=x',
      'https://user@test.openai.azure.com',
      'https://test.openai.azure.com:8443',
    ]) {
      expect(
        () => AiConfiguration(
          provider: AiProvider.azure,
          key: 'key',
          model: 'm',
          endpoint: endpoint,
        ).validate(),
        throwsA(isA<UserFacingException>()),
      );
    }
    expect(
      azure.uri.toString(),
      'https://test.openai.azure.com/openai/v1/chat/completions',
    );
    expect(config.identity, isNot(contains(config.key)));
  });
  test(
    'one compact request, no library metadata; empty output never retries',
    () async {
      var calls = 0;
      final records = <Map<String, Object?>>[];
      final service = PassageService(
        clientFactory: () => MockClient((r) async {
          calls++;
          expect(r.url.host, 'api.openai.com');
          expect(r.headers['Authorization'], 'Bearer test-secret');
          final body = jsonDecode(r.body) as Map;
          expect(body['messages'].length, 2);
          expect(body['max_completion_tokens'], 2500);
          expect(body['response_format']['json_schema']['strict'], true);
          expect(body.containsKey('tools'), false);
          expect(body['store'], false);
          return response(content: '{"items":[]}');
        }),
      );
      final result = await service.extract(
        request,
        const AiPreferences(config),
        onAttempt: (a) async => records.add(a),
      );
      expect(result.result.items, isEmpty);
      expect(calls, 1);
      expect(records.single['usage'], containsPair('prompt_tokens', 120));
      expect(jsonEncode(records), isNot(contains('test-secret')));
    },
  );
  test(
    'Gemini uses its OpenAI-compatible endpoint with Bearer and no store',
    () async {
      final service = PassageService(
        clientFactory: () => MockClient((r) async {
          expect(
            r.url.toString(),
            'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
          );
          expect(r.headers['Authorization'], 'Bearer gemini-secret');
          expect(r.headers.containsKey('api-key'), false);
          final body = jsonDecode(r.body) as Map;
          expect(body.containsKey('store'), false);
          expect(body['model'], 'gemini-flash-latest');
          return response();
        }),
      );
      final result = await service.extract(
        request,
        const AiPreferences(
          AiConfiguration(
            provider: AiProvider.gemini,
            key: 'gemini-secret',
            model: 'gemini-flash-latest',
          ),
        ),
        onAttempt: (_) async {},
      );
      expect(result.configuration.label, 'Google Gemini');
    },
  );
  test(
    'quota failures stop at three attempts and use only configured fallback',
    () async {
      final hosts = <String>[];
      final records = <Map<String, Object?>>[];
      final service = PassageService(
        clientFactory: () => MockClient((r) async {
          hosts.add(r.url.host);
          if (r.url.host == 'api.openai.com') return http.Response('{}', 429);
          expect(r.headers['api-key'], 'azure-secret');
          return response();
        }),
      );
      final result = await service.extract(
        request,
        const AiPreferences(config, azure),
        onAttempt: (a) async => records.add(a),
      );
      expect(hosts, [
        'api.openai.com',
        'api.openai.com',
        'test.openai.azure.com',
      ]);
      expect(result.configuration.provider, AiProvider.azure);
      expect(records.length, 3);
    },
  );
  test(
    'refusal never falls back; truncation is an error, not empty success',
    () async {
      var calls = 0;
      final refused = PassageService(
        clientFactory: () => MockClient((r) async {
          calls++;
          return response(refusal: 'no');
        }),
      );
      await expectLater(
        refused.extract(
          request,
          const AiPreferences(config, azure),
          onAttempt: (_) async {},
        ),
        throwsA(isA<UserFacingException>()),
      );
      expect(calls, 1);
      calls = 0;
      final truncated = PassageService(
        clientFactory: () => MockClient((r) async {
          calls++;
          return response(finish: 'length');
        }),
      );
      await expectLater(
        truncated.extract(
          request,
          const AiPreferences(config),
          onAttempt: (_) async {},
        ),
        throwsA(isA<UserFacingException>()),
      );
      expect(calls, 1);
    },
  );
  test('cancel during an active call does not retry or fall back', () async {
    final entered = Completer<void>(), finish = Completer<http.Response>();
    var calls = 0;
    final records = <Map<String, Object?>>[];
    final service = PassageService(
      clientFactory: () => MockClient((_) {
        calls++;
        entered.complete();
        return finish.future;
      }),
    );
    final future = service.extract(
      request,
      const AiPreferences(config, azure),
      onAttempt: (a) async => records.add(a),
    );
    final assertion = expectLater(future, throwsA(isA<PassageCancelled>()));
    await entered.future;
    service.cancel();
    finish.complete(response());
    await assertion;
    expect(calls, 1);
    expect(records.single['status'], 'cancelled');
  });

  test('local usage write errors never trigger a second paid call', () async {
    var calls = 0;
    final service = PassageService(
      clientFactory: () => MockClient((_) async {
        calls++;
        return response();
      }),
    );
    await expectLater(
      service.extract(
        request,
        const AiPreferences(config, azure),
        onAttempt: (_) async => throw StateError('disk full'),
      ),
      throwsStateError,
    );
    expect(calls, 1);
  });
  test('auth failure goes straight to fallback; JSON mode uses the same local validation', () async {
    var calls = 0;
    final service = PassageService(
      clientFactory: () => MockClient((r) async {
        calls++;
        expect(r.followRedirects, false);
        if (r.url.host == 'api.openai.com') return http.Response('{}', 401);
        expect(jsonDecode(r.body)['response_format'], {'type': 'json_object'});
        return response();
      }),
    );
    const fallback = AiConfiguration(
      provider: AiProvider.azure,
      key: 'key',
      model: 'dep',
      endpoint: 'https://test.openai.azure.com',
      structured: false,
    );
    final r = await service.extract(
      request,
      const AiPreferences(config, fallback),
      onAttempt: (_) async {},
    );
    expect(calls, 2);
    expect(r.result.items.single.term, 'persistent');
  });
  test('invalid budget prevents network calls entirely', () async {
    var calls = 0;
    final service = PassageService(
      clientFactory: () {
        calls++;
        return MockClient((_) async => response());
      },
    );
    await expectLater(
      service.extract(
        PassageRequest('a ' * 7000),
        const AiPreferences(config),
        onAttempt: (_) async {},
      ),
      throwsA(isA<UserFacingException>()),
    );
    expect(calls, 0);
  });
  group('long passages', () {
    final paragraph = List.generate(
      40,
      (i) => 'Sentence $i keeps the persistent effort going.',
    ).join(' ');
    final long = List.filled(12, paragraph).join('\n\n');
    test('splits at boundaries, within budget, keeping every word', () {
      final parts = splitPassage(long);
      expect(parts.length, greaterThan(1));
      for (final p in parts) {
        expect(utf8.encode(p).length, lessThanOrEqualTo(maxPartBytes));
        expect(p, startsWith('Sentence'));
        expect(p, endsWith('going.'));
      }
      expect(parts.join(' ').split(RegExp(r'\s+')), long.split(RegExp(r'\s+')));
      final unbroken = splitPassage('x' * 7000);
      expect(unbroken.map((p) => p.length), [6000, 1000]);
      for (final p in PassageRequest(long).parts()) {
        p.checkBudget(16384);
      }
    });
    test('max items is shared so the merged result fits it', () {
      expect(shareItems(30, [5, 5, 1]).fold(0, (a, b) => a + b), 30);
      expect(shareItems(3, [100, 1, 1]), [1, 1, 1]);
      expect(shareItems(10, [3, 1]), [7, 3]);
      final request = PassageRequest(long, maxItems: 30);
      expect(
        request.parts().fold(0, (a, p) => a + p.maxItems),
        request.maxItems,
      );
      expect(
        () => PassageRequest(long, maxItems: 1).parts(),
        throwsA(isA<UserFacingException>()),
      );
    });
    test('each part is one request; duplicates across parts merge', () async {
      final bodies = <String>[];
      final records = <Map<String, Object?>>[];
      final service = PassageService(
        clientFactory: () => MockClient((r) async {
          bodies.add(jsonDecode(r.body)['messages'][1]['content'] as String);
          return response();
        }),
      );
      final request = PassageRequest(long);
      final parts = request.parts();
      final result = await service.extractParts(
        request,
        const AiPreferences(config),
        onAttempt: (a) async => records.add(a),
      );
      expect(bodies, parts.map((p) => p.text));
      expect(result.complete, true);
      expect(result.result.items.single.term, 'persistent');
      expect(result.result.removed, parts.length - 1);
      expect(records.map((r) => r['part']), [
        for (var i = 1; i <= parts.length; i++) i,
      ]);
      expect(
        validatePassageResult(result.result.json, request).items.length,
        1,
      );
    });
    test(
      'a failed part keeps earlier parts; retry only calls the rest',
      () async {
        final request = PassageRequest(long);
        final total = request.parts().length;
        var calls = 0;
        final failing = PassageService(
          clientFactory: () => MockClient((r) async {
            calls++;
            return calls == 1 ? response() : http.Response('{}', 401);
          }),
        );
        final first = await failing.extractParts(
          request,
          const AiPreferences(config),
          onAttempt: (_) async {},
        );
        expect(calls, 2);
        expect(first.done, {0});
        expect(first.complete, false);
        expect(first.error, isA<UserFacingException>());
        var retries = 0;
        final retry =
            await PassageService(
              clientFactory: () => MockClient((r) async {
                retries++;
                return response(content: '{"items":[]}');
              }),
            ).extractParts(
              request,
              const AiPreferences(config),
              onAttempt: (_) async {},
              done: first.done,
              previous: first.result,
            );
        expect(retries, total - 1);
        expect(retry.complete, true);
        expect(retry.result.items.single.term, 'persistent');
      },
    );
    test('refusal skips only that part', () async {
      var calls = 0;
      final result =
          await PassageService(
            clientFactory: () => MockClient((r) async {
              calls++;
              return calls == 1 ? response(refusal: 'no') : response();
            }),
          ).extractParts(
            PassageRequest(long),
            const AiPreferences(config),
            onAttempt: (_) async {},
          );
      expect(result.done.contains(0), false);
      expect(result.done.length, result.parts - 1);
      expect(calls, result.parts);
    });
  });
  group('persisted passage workflow', () {
    late Database db;
    late LibraryRepository library;
    late PassageRepository repo;
    late String deck;
    Future<String> completed() async {
      final id = await repo.create(request, const AiPreferences(config));
      await repo.attempt(id, {
        'provider': 'openai',
        'usage': {'prompt_tokens': 12},
      });
      await repo.complete(
        id,
        ExtractionResponse(
          validatePassageResult(output([item]), request),
          config,
        ),
      );
      return id;
    }

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      db = await openVocabularyDatabase(
        databaseFactoryFfiNoIsolate,
        inMemoryDatabasePath,
      );
      library = LibraryRepository(db);
      repo = PassageRepository(library);
      deck = (await library.decks()).single.id;
    });
    tearDown(() async => db.close());
    test(
      'partial jobs are not cache hits but resume their done parts',
      () async {
        final long = List.filled(
          3,
          List.filled(300, 'The persistent effort helped.').join(' '),
        ).join('\n\n');
        final request = PassageRequest(long);
        const prefs = AiPreferences(config);
        final key = request.cacheKey(prefs.identity);
        final id = await repo.create(request, prefs);
        final parts = request.parts().length;
        await repo.attempt(id, {
          'status': 'success',
          'part': 2,
          'parts': parts,
        });
        await repo.attempt(id, {'status': 'error', 'part': 3, 'parts': parts});
        final result = validatePassageResult(output([item]), request);
        await repo.completeParts(
          id,
          PartsExtraction(result, config, {1}, parts, null),
          missing: 'Mới trích 1/$parts phần.',
        );
        expect(await repo.cached(key), isNull);
        final partial = (await repo.partial(key, request))!;
        expect(partial.id, id);
        expect(partial.done, {1});
        expect(partial.result.items.single.term, 'persistent');
        expect(await repo.approve(id, deck, [const ReviewedItem(item)]), 1);
        await repo.completeParts(
          id,
          PartsExtraction(result, null, {0, 1, 2}, parts, null),
        );
        expect(await repo.cached(key), id);
        expect((await repo.job(id))['provider'], 'openai');
      },
    );
    test(
      'cache/history contain no keys; approving twice preserves reviewed cards',
      () async {
        final id = await completed();
        expect(
          await repo.cached(
            request.cacheKey(const AiPreferences(config).identity),
          ),
          id,
        );
        expect(jsonEncode(await repo.job(id)), isNot(contains(config.key)));
        expect(await db.query('cards'), isEmpty);
        expect(await repo.approve(id, deck, [const ReviewedItem(item)]), 1);
        await library.review(
          (await library.studyQueue()).single,
          Rating.good,
          'review',
        );
        final cards = await db.query('cards');
        expect(await repo.approve(id, deck, [const ReviewedItem(item)]), 0);
        expect(await db.query('cards'), cards);
        expect(
          (await db.query('sense_origins')).single['estimated_level'],
          'B2',
        );
        await repo.delete(id);
        expect((await db.query('sense_origins')).single['job_id'], null);
        expect(await db.query('cards'), cards);
      },
    );
    test('conflicting meanings create separate senses or explicitly reuse the old one', () async {
      await library.addWord(term: item.term, meaning: 'kiên trì', deckId: deck);
      final old = (await repo.matches(item.term)).single;
      final id = await completed();
      expect(
        await repo.approve(id, deck, [
          ReviewedItem(item, existingSenseId: old.senseId),
        ]),
        0,
      );
      expect((await library.vocabulary()).single.meaning, 'kiên trì');
      expect(await db.query('sense_origins'), isEmpty);
      expect(await repo.approve(id, deck, [const ReviewedItem(item)]), 1);
      expect((await db.query('senses')).length, 2);
    });
    test('invalid selection rolls back the entire batch', () async {
      final id = await completed();
      await expectLater(
        repo.approve(id, deck, [
          const ReviewedItem(item),
          const ReviewedItem(PassageItem('invented', 'B2', 'bịa')),
        ]),
        throwsA(isA<UserFacingException>()),
      );
      expect(await db.query('senses'), isEmpty);
      expect(await db.query('entries'), isEmpty);
    });
    test('backup v2 includes long passages/results/provenance and reads old v1 backups', () async {
      final id = await completed();
      await repo.approve(id, deck, [const ReviewedItem(item)]);
      await db.update(
        'passage_jobs',
        {'source_text': 'x' * 6000},
        where: 'id=?',
        whereArgs: [id],
      );
      final bytes = await BackupService(db).export();
      expect(BackupService(db).inspect(bytes).passages, 1);
      await BackupService(db).restore(bytes, saveRecovery: (_) async {});
      expect((await repo.job(id))['source_text'], 'x' * 6000);
      expect((await db.query('sense_origins')).length, 1);
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      root['version'] = 1;
      root['db_version'] = 1;
      root['data'].remove('passage_jobs');
      root['data'].remove('sense_origins');
      root['data'].remove('import_batches');
      for (final row in root['data']['senses']) {
        for (final field in ['part_of_speech', 'pronunciation', 'note']) {
          row.remove(field);
        }
      }
      root['sha256'] = sha256
          .convert(utf8.encode(jsonEncode(root['data'])))
          .toString();
      final legacy = Uint8List.fromList(utf8.encode(jsonEncode(root)));
      await BackupService(db).restore(legacy, saveRecovery: (_) async {});
      expect(await repo.history(), isEmpty);
      expect((await library.vocabulary()).length, 1);
    });
    testWidgets('long passage keeps done parts and continues only the rest', (
      tester,
    ) async {
      await const AiConfigurationStore().save(const AiPreferences(config));
      final long = List.filled(
        3,
        List.filled(300, 'The persistent effort helped.').join(' '),
      ).join('\n\n');
      final parts = PassageRequest(long).parts().length;
      var calls = 0;
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: PassagePage(
            library: library,
            serviceFactory: () => PassageService(
              clientFactory: () => MockClient((_) async {
                calls++;
                if (fail && calls > 1) return http.Response('{}', 401);
                return response();
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Passage tiếng Anh'),
        long,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.textContaining('Chia thành $parts phần'), findsOneWidget);
      await tester.tap(find.text('Trích từ (ưu tiên cache)'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.textContaining('Mới trích 1/$parts phần'), findsOneWidget);
      fail = false;
      await tester.ensureVisible(find.text('Trích tiếp phần còn lại'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trích tiếp phần còn lại'));
      await tester.pumpAndSettle();
      expect(calls, 2 + parts - 1);
      expect(find.text('Trích tiếp phần còn lại'), findsNothing);
      expect((await repo.history()).length, 1);
      expect((await repo.history()).single['error_text'], isNull);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('overlong paste is preserved and blocked before an API call', (
      tester,
    ) async {
      await const AiConfigurationStore().save(const AiPreferences(config));
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PassagePage(
            library: library,
            serviceFactory: () => PassageService(
              clientFactory: () => MockClient((_) async {
                calls++;
                return response();
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Passage tiếng Anh');
      await tester.enterText(field, 'a' * 100001);
      expect(tester.widget<TextField>(field).controller!.text.length, 100001);
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trích từ (ưu tiên cache)'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(await repo.history(), isEmpty);
      expect(find.textContaining('Cần passage 1–100.000 ký tự'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
      'mobile passage flow reviews, edits and saves without extra API calls',
      (tester) async {
        await const AiConfigurationStore().save(const AiPreferences(config));
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: PassagePage(
              library: library,
              serviceFactory: () => PassageService(
                clientFactory: () => MockClient((_) async {
                  calls++;
                  return response();
                }),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Passage tiếng Anh'),
          request.text,
        );
        FocusManager.instance.primaryFocus?.unfocus();
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Trích từ (ưu tiên cache)'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Trích từ (ưu tiên cache)'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('persistent'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('persistent'), findsOneWidget);
        expect(await db.query('cards'), isEmpty);
        await tester.scrollUntilVisible(
          find.widgetWithText(TextField, 'Nghĩa ngắn · có thể sửa'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Nghĩa ngắn · có thể sửa'),
          'bền bỉ',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Duyệt các mục đã chọn và đưa vào học'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Duyệt các mục đã chọn và đưa vào học'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect((await library.vocabulary()).single.meaning, 'bền bỉ');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
  test('schema 1 upgrades without losing words, cards or reviews', () async {
    final dir = await Directory.systemTemp.createTemp('vocabapp-migration');
    final path = '${dir.path}/vocabulary.db';
    final first = await openVocabularyDatabase(
      databaseFactoryFfiNoIsolate,
      path,
    );
    final library = LibraryRepository(first);
    await library.addWord(
      term: 'retain',
      meaning: 'giữ lại',
      deckId: (await library.decks()).single.id,
    );
    await library.review(
      (await library.studyQueue()).single,
      Rating.good,
      'persisted',
    );
    final cards = await first.query('cards');
    await dropSyncSchema(first);
    await first.execute('DROP TABLE import_batches');
    for (final field in ['part_of_speech', 'pronunciation', 'note']) {
      await first.execute('ALTER TABLE senses DROP COLUMN $field');
    }
    await first.execute('DROP TABLE sense_origins');
    await first.execute('DROP TABLE passage_jobs');
    await first.setVersion(1);
    await first.close();
    final upgraded = await openVocabularyDatabase(
      databaseFactoryFfiNoIsolate,
      path,
    );
    try {
      expect(await upgraded.getVersion(), 4);
      expect(await upgraded.query('cards'), cards);
      expect((await upgraded.query('review_events')).single['id'], 'persisted');
      expect(await upgraded.query('passage_jobs'), isEmpty);
    } finally {
      await upgraded.close();
      await dir.delete(recursive: true);
    }
  });
}
