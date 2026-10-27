import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocabapp/data/database.dart';
import 'package:vocabapp/data/library_repository.dart';
import 'package:vocabapp/ui/app.dart';
import 'package:vocabapp/ui/review_page.dart';
import 'package:vocabapp/ui/ui_scale.dart';

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
    await tester.ensureVisible(find.text('Nhớ'));
    await tester.pumpAndSettle();
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

  testWidgets('UI zoom scales layout and responds to keyboard shortcuts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scale = UiScaleController();
    addTearDown(scale.dispose);
    await tester.pumpWidget(VocabApp(repository: repo, uiScale: scale));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);

    await tester.tap(find.text('Cài đặt').last);
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Phóng to'));
      await tester.pumpAndSettle();
    }
    expect(scale.value, 1.5);
    expect(find.text('150%'), findsOneWidget);
    // 1200 px at 150% is an 800 px logical viewport: compact navigation.
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(scale.value, 1);
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'UI zoom ignores a corrupt preference file and persists the last value',
    () async {
      final dir = Directory.systemTemp.createTempSync('vocab-ui');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/ui.json')..writeAsStringSync('{oops');
      final scale = await UiScaleController.load(file);
      addTearDown(scale.dispose);
      expect(scale.value, 1);
      scale
        ..zoomOut()
        ..zoomIn()
        ..zoomIn();
      await scale.saved;
      expect(scale.value, 1.1);
      final reloaded = await UiScaleController.load(file);
      addTearDown(reloaded.dispose);
      expect(reloaded.value, 1.1);
    },
  );
}
