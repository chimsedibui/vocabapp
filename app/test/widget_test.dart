import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocabapp/data/database.dart';
import 'package:vocabapp/data/library_repository.dart';
import 'package:vocabapp/ui/app.dart';
import 'package:vocabapp/ui/review_page.dart';

void main() {
  tz.initializeTimeZones();
  late Database db;
  late LibraryRepository repo;
  setUp(() async {
    db = await openVocabularyDatabase(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    repo = LibraryRepository(db);
  });
  tearDown(() async => db.close());

  testWidgets('empty library can add an approved word and study offline', (
    tester,
  ) async {
    await tester.pumpWidget(VocabApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.text('Thêm từ đầu tiên'), findsOneWidget);
    await tester.tap(find.text('Thêm từ đầu tiên'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'retain');
    await tester.enterText(fields.at(1), 'giữ lại');
    await tester.tap(find.text('Lưu và đưa vào học'));
    await tester.pumpAndSettle();
    expect((await repo.stats()).fresh, 1);
    await tester.tap(find.text('Học ngay'));
    await tester.pumpAndSettle();
    expect(find.text('retain'), findsOneWidget);
    expect(find.text('giữ lại'), findsNothing);
    expect(find.text('Nhớ'), findsNothing);
    await tester.tap(find.text('Hiện nghĩa'));
    await tester.pumpAndSettle();
    expect(find.text('giữ lại'), findsOneWidget);
    await tester.tap(find.text('Nhớ'));
    await tester.pumpAndSettle();
    expect(find.text('Đã lưu 1 lượt ôn'), findsOneWidget);
    expect((await db.query('review_events')).length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'review only records after reveal and persists when route closes',
    (tester) async {
      await repo.addWord(
        term: 'retain',
        meaning: 'giữ lại',
        deckId: (await repo.decks()).single.id,
      );
      await tester.pumpWidget(MaterialApp(home: ReviewPage(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Quên'), findsNothing);
      await tester.tap(find.text('Hiện nghĩa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quên'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect((await db.query('cards')).single['state'], 'relearning');
    },
  );

  testWidgets(
    'creating a selected group refreshes without using stale dropdown items',
    (tester) async {
      await tester.pumpWidget(VocabApp(repository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thư viện').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tạo nhóm'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Công việc');
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Công việc (0)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mobile large text stays usable on all navigation screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(VocabApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thư viện').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cài đặt').last);
    await tester.pumpAndSettle();
    expect(find.text('Nhịp học của bạn'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
