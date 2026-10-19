import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocabapp/data/database.dart';
import 'package:vocabapp/data/library_repository.dart';
import 'package:vocabapp/domain/models.dart';
import 'package:vocabapp/domain/scheduler.dart';
import 'package:vocabapp/services/backup_service.dart';

void main() {
  tz.initializeTimeZones();
  late Database db, other;
  late LibraryRepository repo;
  setUp(() async {
    db = await openVocabularyDatabase(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    other = await openVocabularyDatabase(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
      singleInstance: false,
    );
    repo = LibraryRepository(db);
    await repo.addWord(
      term: 'retain',
      meaning: 'giữ lại',
      deckId: (await repo.decks()).single.id,
    );
    await repo.review(
      (await repo.studyQueue()).single,
      Rating.good,
      'stored-review',
    );
  });
  tearDown(() async {
    await db.close();
    await other.close();
  });

  test('backup round-trip preserves all identities and due, destination device stays unique', () async {
    final service = BackupService(db);
    final backup = await service.export();
    expect(service.inspect(backup).reviews, 1);
    final device = (await other.query('settings')).single['device_id'];
    Uint8List? recovery;
    await BackupService(other)
        .restore(backup, saveRecovery: (b) async => recovery = b);
    expect(recovery, isNotNull);
    expect((await other.query('settings')).single['device_id'], device);
    expect(await other.query('cards'), await db.query('cards'));
    expect(await other.query('review_events'), await db.query('review_events'));
    expect(BackupService(other).inspect(recovery!).entries, 0);
  });

  test(
    'modified or unsupported backups are rejected before deleting anything',
    () async {
      final root = jsonDecode(
        utf8.decode(await BackupService(db).export()),
      ) as Map<String, dynamic>;
      root['version'] = 99;
      await expectLater(
        BackupService(db).restore(
          Uint8List.fromList(utf8.encode(jsonEncode(root))),
          saveRecovery: (_) async {},
        ),
        throwsA(isA<UserFacingException>()),
      );
      root['version'] = 1;
      root['data']['entries'][0]['term'] = 'modified';
      expect(
        () =>
            BackupService(db)
                .inspect(Uint8List.fromList(utf8.encode(jsonEncode(root)))),
        throwsA(isA<UserFacingException>()),
      );
      expect((await repo.vocabulary()).single.term, 'retain');
    },
  );

  test(
    'foreign-key failure rolls back replacement and preserves old library',
    () async {
      final root = jsonDecode(
        utf8.decode(await BackupService(db).export()),
      ) as Map<String, dynamic>;
      root['data']['cards'][0]['sense_id'] = 'missing';
      root['sha256'] = sha256
          .convert(utf8.encode(jsonEncode(root['data'])))
          .toString();
      await expectLater(
        BackupService(db).restore(
          Uint8List.fromList(utf8.encode(jsonEncode(root))),
          saveRecovery: (_) async {},
        ),
        throwsA(isA<UserFacingException>()),
      );
      expect((await db.query('review_events')).single['id'], 'stored-review');
      expect((await repo.vocabulary()).single.term, 'retain');
    },
  );

  test('recovery file write failure aborts restore', () async {
    final backup = await BackupService(db).export();
    await expectLater(
      BackupService(other).restore(
        backup,
        saveRecovery: (_) async => throw StateError('disk full'),
      ),
      throwsA(isA<UserFacingException>()),
    );
    expect((await other.query('entries')), isEmpty);
    expect((await db.query('review_events')).length, 1);
  });
}
