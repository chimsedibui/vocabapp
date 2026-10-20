import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocabapp/data/database.dart';
import 'package:vocabapp/data/import_repository.dart';
import 'package:vocabapp/data/library_repository.dart';
import 'package:vocabapp/domain/import_data.dart';
import 'package:vocabapp/domain/models.dart';
import 'package:vocabapp/domain/scheduler.dart';
import 'package:vocabapp/services/backup_service.dart';
import 'package:vocabapp/ui/import_page.dart';

import 'sync_schema_helper.dart';

List<ImportTable> parse(
  String text, {
  String extension = 'json',
  String delimiter = ',',
}) => parseImport({
  'bytes': utf8.encode(text),
  'extension': extension,
  'delimiter': delimiter,
});
ImportRow row(
  int n, {
  String term = 'retain',
  String? meaning = 'giữ lại',
  String deck = 'daily',
  String name = 'Từ vựng hằng ngày',
  String sense = 'primary',
  Map<String, Object?> extra = const {},
}) => validateImportRow(n, {
  'term': term,
  'meaning': meaning,
  'deck_key': deck,
  'deck_name': name,
  'sense_key': sense,
  'source_language': 'en',
  'target_language': 'vi',
  ...extra,
});
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (i >= 30 && find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  tz.initializeTimeZones();
  test('JSON root arrays, named and nested lists flatten with unambiguous pointers', () {
    final tables = parse(
      '{"data":{"vocabulary":[{"word":"retain","translation":{"vi":"giữ lại"},"literal.key":"x"}]},"other":[]}',
    );
    expect(tables.map((t) => t.name), ['/data/vocabulary', '/other']);
    expect(tables.first.rows.single['/translation/vi'], 'giữ lại');
    expect(tables.first.rows.single['/literal.key'], 'x');
    expect(suggestMapping(tables.first.columns)['term'], '/word');
    expect(parse('[{"term":"a"}]').single.name, '/');
    expect(parse('[1,{"term":true}]').single.rows.first, contains('!error'));
  });
  test('duplicate JSON keys including escaped keys, bad schema and trailing syntax fail', () {
    for (final text in [
      r'{"items":[{"term":"one","\u0074erm":"two"}]}',
      '{"schema_version":"2.0","items":[]}',
      '{"items":[]} trailing',
      '{"items":[}',
      '{"x":1}',
    ]) {
      expect(() => parse(text), throwsFormatException, reason: text);
    }
    expect(
      parse(
        '{"schema_version":"1.0","items":[{"term":"a","status":"approved"}]}',
      ).single.rows.single,
      contains('!error'),
    );
  });
  test('CSV handles BOM, commas, escaped quotes, embedded newline and final empty cells', () {
    final table = parse(
      '\uFEFFword,definition,note\r\n"follow up","theo dõi, tiếp tục","nói ""hello""\nxong"\r\nretain,giữ lại,\r\n\r\n',
      extension: 'csv',
    ).single;
    expect(table.rows.length, 2);
    expect(table.rows.first['/definition'], 'theo dõi, tiếp tục');
    expect(table.rows.first['/note'], 'nói "hello"\nxong');
    expect(table.rows.last['/note'], '');
    expect(
      parse(
        'word;meaning\na;b',
        extension: 'csv',
        delimiter: ';',
      ).single.columns,
      ['/word', '/meaning'],
    );
  });
  test('bad quotes/duplicate headers fail; short/long CSV records are flagged, never silently fixed', () {
    for (final text in [
      'word,word\na,b',
      ',meaning\na,b',
      'word,meaning\n"oops,a',
      'word,meaning\n"a"oops,b',
    ]) {
      expect(() => parse(text, extension: 'csv'), throwsFormatException);
    }
    final rows = parse('word,meaning\na\nb,c,d', extension: 'csv').single.rows;
    expect(rows.every((r) => r.containsKey('!error')), true);
  });
  test('byte, row and depth limits reject input without truncating', () {
    expect(
      () => parseImport({
        'bytes': Uint8List(importMaxBytes + 1),
        'extension': 'json',
      }),
      throwsFormatException,
    );
    expect(
      () => parse(jsonEncode(List.generate(10001, (_) => {'term': 'x'}))),
      throwsFormatException,
    );
    expect(() => parse('${'[' * 33}${']' * 33}'), throwsFormatException);
    expect(
      () => parseImport({
        'bytes': [255, 254],
        'extension': 'csv',
      }),
      throwsFormatException,
    );
  });
  test('normalization, missing meanings and type errors are visible; identity preserves case', () {
    final valid = row(1, term: '  cafe\u0301   house ', meaning: null);
    expect(valid.text('term'), 'café house');
    expect(valid.errors, isEmpty);
    expect(valid.values['meaning'], null);
    expect(row(2, extra: {'term': 123}).errors.join(), contains('chuỗi'));
    expect(
      row(3, extra: {'source_language': 'fr'}).errors.join(),
      contains('chỉ nhập'),
    );
    expect(row(4, extra: {'part_of_speech': 'invalid'}).errors, isNotEmpty);
    expect(row(5, term: 'US').entryKey, isNot(row(6, term: 'us').entryKey));
  });
  test(
    'CSV export quotes safely and prevents formulas; JSON remains lossless',
    () {
      final original = row(
        1,
        term: '=HYPERLINK("x")',
        meaning: 'nghĩa, có\nxuống dòng',
        extra: {'note': '  @SUM(1)'},
      );
      final csv = exportImportCsv([original]);
      final parsed = parse(csv, extension: 'csv').single.rows.single;
      expect(parsed['/term'], '\'=HYPERLINK("x")');
      expect(parsed['/meaning'], original.values['meaning']);
      expect(parsed['/note'], "'@SUM(1)");
      expect(original.values['term'], '=HYPERLINK("x")');
      final report = parse(
        exportImportCsv([original], errors: true, messages: {1: '=bad'}),
        extension: 'csv',
      ).single.rows.single;
      expect(report['/validation'], "'=bad");
    },
  );

  group('database preview and commit', () {
    late Database db;
    late LibraryRepository library;
    late ImportRepository repo;
    setUp(() async {
      db = await openVocabularyDatabase(
        databaseFactoryFfiNoIsolate,
        inMemoryDatabasePath,
      );
      library = LibraryRepository(db);
      repo = ImportRepository(library);
    });
    tearDown(() async => db.close());
    Future<ImportResult> commit(List<ImportRow> rows, {bool approve = false}) =>
        repo.commit(
          rows,
          approve: approve,
          fileName: 'words.json',
          fileHash: 'hash',
        );
    test('preview has no writes; import requires approval and keeps metadata and audit', () async {
      final rows = [
        row(
          1,
          extra: {
            'part_of_speech': 'verb',
            'pronunciation': '/rɪˈteɪn/',
            'note': 'Ghi chú',
          },
        ),
      ];
      final plan = planImport(rows, {1}, await repo.snapshot());
      expect(plan.single.status, 'Mới');
      expect(await db.query('entries'), isEmpty);
      final r = await commit(rows);
      expect(r.senses, 1);
      expect(await db.query('cards'), isEmpty);
      expect((await db.query('senses')).single['part_of_speech'], 'verb');
      expect((await db.query('senses')).single['note'], 'Ghi chú');
      expect((await db.query('import_batches')).single['selected_rows'], 1);
      final promoted = await commit(rows, approve: true);
      expect(promoted.senses, 0);
      expect(promoted.approved, 1);
      expect((await db.query('cards')).length, 1);
    });
    test('exact duplicates and multiple decks/senses never duplicate or reset cards', () async {
      await commit([row(1)], approve: true);
      await library.review(
        (await library.studyQueue()).single,
        Rating.good,
        'review',
      );
      final cards = await db.query('cards');
      final r = await commit([
        row(1),
        row(2),
        row(3, deck: 'work', name: 'Công việc'),
        row(4, term: 'bank', sense: 'river', meaning: 'bờ sông'),
      ], approve: true);
      expect(r.senses, 1);
      expect(r.memberships, 2);
      expect(
        (await db.query('cards'))
            .firstWhere((c) => c['id'] == cards.single['id']),
        cards.single,
      );
      expect((await db.query('review_events')).single['id'], 'review');
    });
    test('conflicts in file are resolved by selection; database conflicts cannot overwrite', () async {
      final rows = [row(1), row(2, meaning: 'giữ gìn')];
      final snap = await repo.snapshot();
      expect(planImport(rows, {1, 2}, snap).every((c) => !c.valid), true);
      expect(planImport(rows, {1}, snap).first.valid, true);
      await commit([rows.first], approve: true);
      await expectLater(
        commit([row(3, meaning: 'khác')], approve: true),
        throwsA(isA<UserFacingException>()),
      );
      expect((await library.vocabulary()).single.meaning, 'giữ lại');
      expect((await db.query('import_batches')).length, 1);
      await commit([row(3, sense: 'another', meaning: 'khác')]);
      expect((await db.query('senses')).length, 2);
    });
    test('empty incoming fields never clear content; absent meaning remains draft even when approval is on', () async {
      await commit([
        row(1, extra: {'note': 'giữ metadata'}),
      ], approve: true);
      final r = await commit([
        row(1, meaning: null),
        row(2, term: 'resilient', meaning: null),
      ], approve: true);
      expect(r.approved, 0);
      expect((await db.query('cards')).length, 1);
      final existing = (await db.query('senses'))
          .firstWhere((s) => s['meaning'] == 'giữ lại');
      expect(existing['note'], 'giữ metadata');
      expect((await library.stats()).drafts, 1);
    });
    test('write-boundary revalidation catches stale previews and rolls back the whole batch', () async {
      final rows = [row(1, term: 'first'), row(2)];
      expect(
        planImport(rows, {1, 2}, await repo.snapshot()).every((r) => r.valid),
        true,
      );
      await commit([row(1, meaning: 'DB đổi sau preview')], approve: true);
      await expectLater(commit(rows), throwsA(isA<UserFacingException>()));
      expect((await db.query('entries')).length, 1);
      await db.execute(
        "CREATE TRIGGER fail_audit BEFORE INSERT ON import_batches BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );
      await expectLater(
        commit([row(1, term: 'new')], approve: true),
        throwsA(anything),
      );
      expect((await db.query('entries')).length, 1);
      expect((await db.query('cards')).length, 1);
    });
    test('same deck key with different names is a conflict; case-only matches warn without merging', () async {
      final rows = [row(1), row(2, term: 'other', name: 'Tên khác')];
      expect(
        planImport(rows, {1, 2}, await repo.snapshot()).every((r) => !r.valid),
        true,
      );
      await commit([row(1, term: 'US')]);
      expect(
        planImport(
          [row(1, term: 'us')],
          {1},
          await repo.snapshot(),
        ).single.warnings.join(),
        contains('hoa/thường'),
      );
      await commit([row(1, term: 'us')]);
      expect((await db.query('entries')).length, 2);
    });
    test('backup3 retains metadata/audit and restores a real version2-shaped snapshot', () async {
      await commit([
        row(1, extra: {'note': 'note', 'part_of_speech': 'verb'}),
      ], approve: true);
      final service = BackupService(db),
          bytes = await BackupService(db).export();
      await service.restore(bytes, saveRecovery: (_) async {});
      expect((await db.query('senses')).single['note'], 'note');
      expect((await db.query('import_batches')).length, 1);
      final root = jsonDecode(utf8.decode(bytes));
      root['version'] = 2;
      root['db_version'] = 2;
      root['data'].remove('import_batches');
      for (final r in root['data']['senses']) {
        for (final f in ['part_of_speech', 'pronunciation', 'note']) {
          r.remove(f);
        }
      }
      root['sha256'] = sha256
          .convert(utf8.encode(jsonEncode(root['data'])))
          .toString();
      await service.restore(
        Uint8List.fromList(utf8.encode(jsonEncode(root))),
        saveRecovery: (_) async {},
      );
      expect((await db.query('senses')).single['note'], null);
      expect(await db.query('import_batches'), isEmpty);
      expect((await db.query('cards')).length, 1);
    });
    testWidgets(
      'mobile large text can map nested JSON columns without writing to the library',
      (tester) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            home: ImportPage(
              library: library,
              initialName: 'nested.json',
              initialBytes: Uint8List.fromList(
                utf8.encode(
                  '{"vocabulary":[{"english":"retained","gloss":{"vi":"giữ lại"}}]}',
                ),
              ),
            ),
          ),
        );
        await settle(tester);
        final term = find.widgetWithText(DropdownButtonFormField<String>, 'Từ');
        await tester.scrollUntilVisible(
          term,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(term);
        await tester.pumpAndSettle();
        await tester.tap(find.text('english').last);
        await settle(tester);
        final meaning = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Nghĩa',
        );
        await tester.scrollUntilVisible(
          meaning,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(meaning);
        await tester.pumpAndSettle();
        await tester.tap(find.text('gloss › vi').last);
        await settle(tester);
        await tester.scrollUntilVisible(
          find.byType(PaginatedDataTable),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('retained'), findsOneWidget);
        expect(find.text('giữ lại'), findsOneWidget);
        expect(await db.query('entries'), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'JSON table preview, row editing and explicit approval import without prior writes',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: ImportPage(
              library: library,
              initialName: 'words.json',
              initialBytes: Uint8List.fromList(
                utf8.encode(
                  '[{"word":"retain","definition":"giữ lại"},{"word":42,"definition":"lỗi kiểu"}]',
                ),
              ),
            ),
          ),
        );
        await settle(tester);
        expect(find.byType(PaginatedDataTable), findsOneWidget);
        expect(await db.query('entries'), isEmpty);
        expect(find.textContaining('1 lỗi/xung đột đang chọn'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byTooltip('Sửa dòng 2'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byTooltip('Sửa dòng 2'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Từ'),
          'resilient',
        );
        await tester.tap(find.text('Áp dụng và kiểm tra lại'));
        await settle(tester);
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.textContaining('0 lỗi/xung đột đang chọn'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Duyệt những dòng có nghĩa và đưa vào học'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Duyệt những dòng có nghĩa và đưa vào học'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Nhập các dòng đã chọn'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nhập các dòng đã chọn'));
        await tester.pumpAndSettle();
        expect(await db.query('entries'), isEmpty);
        await tester.tap(find.text('Xác nhận nhập'));
        await settle(tester);
        expect((await db.query('entries')).length, 2);
        expect((await db.query('cards')).length, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
  test('database2 migration preserves reviews and adds metadata/audit without reseeding', () async {
    final dir = await Directory.systemTemp.createTemp('vocabapp-import');
    final path = '${dir.path}/db';
    final first = await openVocabularyDatabase(
      databaseFactoryFfiNoIsolate,
      path,
    );
    final lib = LibraryRepository(first);
    await lib.addWord(
      term: 'retain',
      meaning: 'giữ lại',
      deckId: (await lib.decks()).single.id,
    );
    await lib.review((await lib.studyQueue()).single, Rating.good, 'review');
    final cards = await first.query('cards');
    await dropSyncSchema(first);
    await first.execute('DROP TABLE import_batches');
    for (final f in ['part_of_speech', 'pronunciation', 'note']) {
      await first.execute('ALTER TABLE senses DROP COLUMN $f');
    }
    await first.setVersion(2);
    await first.close();
    final db = await openVocabularyDatabase(databaseFactoryFfiNoIsolate, path);
    try {
      expect(await db.getVersion(), 4);
      expect(await db.query('cards'), cards);
      expect((await db.query('review_events')).single['id'], 'review');
      expect(await db.query('import_batches'), isEmpty);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
