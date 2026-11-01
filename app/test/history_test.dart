import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocabapp/data/database.dart';
import 'package:vocabapp/data/library_repository.dart';
import 'package:vocabapp/data/snapshots.dart';
import 'package:vocabapp/services/backup_service.dart';

import 'sync_schema_helper.dart';

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

  Future<String> addRetain() async {
    await repo.addWord(
      term: 'retain',
      meaning: 'giữ lại',
      deckId: (await repo.decks()).single.id,
      partOfSpeech: 'verb',
    );
    return (await repo.vocabulary()).single.senseId;
  }

  test('SCD2: each edit closes the previous version back to back', () async {
    final sense = await addRetain();
    expect(await repo.history(sense), isEmpty);
    await repo.saveMeaning(sense, 'giữ lại; duy trì', approve: true);
    await repo.saveMeaning(
      sense,
      'duy trì',
      approve: true,
      details: (partOfSpeech: 'verb', pronunciation: 'rɪˈteɪn'),
    );
    // A save that changes nothing tracked adds no version.
    await repo.saveMeaning(sense, 'duy trì', approve: true);
    final versions = await repo.history(sense);
    expect(versions.map((v) => v.meaning), ['giữ lại; duy trì', 'giữ lại']);
    expect(versions.last.partOfSpeech, 'verb');
    expect(versions.first.validFrom, versions.last.validTo);
    expect(versions.last.validFrom, isNotNull);

    await repo.restoreVersion(sense, versions.last);
    final word = (await repo.vocabulary()).single;
    expect(word.meaning, 'giữ lại');
    expect(word.pronunciation, isNull);
    expect((await repo.history(sense)).first.meaning, 'duy trì');

    await db.delete('cards');
    await db.delete('senses', where: 'id=?', whereArgs: [sense]);
    expect((await repo.history(sense)).first.deleted, true);
  });

  test(
    'history travels in backups; restoring writes no new versions',
    () async {
      final sense = await addRetain();
      await repo.saveMeaning(sense, 'duy trì', approve: true);
      final bytes = await BackupService(db).export();
      await repo.saveMeaning(sense, 'khác', approve: true);
      expect((await repo.history(sense)).length, 2);
      await BackupService(db).restore(bytes, saveRecovery: (_) async {});
      final versions = await repo.history(sense);
      expect(versions.map((v) => v.meaning), ['giữ lại']);
      expect(await db.query('sync_meta', where: "key='history_off'"), isEmpty);
      await repo.saveMeaning(sense, 'mới', approve: true);
      expect((await repo.history(sense)).length, 2);
    },
  );

  group('snapshots', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vocabapp-snapshots');
    });
    tearDown(() async => dir.delete(recursive: true));

    test('one copy per new app version, newest 5 kept', () async {
      final snapshots = DatabaseSnapshots(dir);
      expect(await snapshots.beforeOpen('0.3.2'), isNull);
      final live = await openVocabularyDatabase(
        databaseFactoryFfiNoIsolate,
        p.join(dir.path, 'vocabulary.db'),
      );
      await LibraryRepository(live).addWord(
        term: 'retain',
        meaning: 'giữ lại',
        deckId: (await LibraryRepository(live).decks()).single.id,
      );
      await live.close();
      expect(await snapshots.beforeOpen('0.3.2'), isNull);
      final first = await snapshots.beforeOpen('0.3.3');
      expect(DatabaseSnapshots.version(first!), '0.3.3');
      expect(DatabaseSnapshots.takenAt(first), isNotNull);
      for (final v in ['0.3.4', '0.3.5', '0.3.6', '0.3.7', '0.3.8']) {
        await snapshots.beforeOpen(v);
      }
      final kept = await snapshots.list();
      expect(kept.length, 5);
      expect(kept.map(DatabaseSnapshots.version), isNot(contains('0.3.3')));
    });

    test('an old-schema snapshot restores through the backup path', () async {
      final path = p.join(dir.path, 'vocabulary.db');
      final old = await openVocabularyDatabase(
        databaseFactoryFfiNoIsolate,
        path,
      );
      final oldRepo = LibraryRepository(old);
      await oldRepo.addWord(
        term: 'retain',
        meaning: 'giữ lại',
        deckId: (await oldRepo.decks()).single.id,
      );
      await dropSyncSchema(old);
      await old.setVersion(3);
      await old.close();
      final snapshots = DatabaseSnapshots(dir);
      final file = (await snapshots.beforeOpen('0.3.3'))!;
      final bytes = await snapshots.exportBackup(
        file,
        databaseFactoryFfiNoIsolate,
      );
      expect(BackupService(db).inspect(bytes).entries, 1);
      await BackupService(db).restore(bytes, saveRecovery: (_) async {});
      expect((await repo.vocabulary()).single.term, 'retain');
      expect(
        await Directory(p.join(dir.path, 'snapshots', 'work')).exists(),
        false,
      );
    });
  });
}
