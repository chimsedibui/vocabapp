import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

Future<Database> openAppDatabase() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final factory = Platform.isAndroid || Platform.isIOS
      ? mobile.databaseFactory
      : databaseFactoryFfi;
  return openVocabularyDatabase(factory, p.join(dir.path, 'vocabulary.db'));
}

Future<Database> openVocabularyDatabase(
  DatabaseFactory factory,
  String path, {
  bool singleInstance = true,
}) => factory.openDatabase(
  path,
  options: OpenDatabaseOptions(
    singleInstance: singleInstance,
    version: 3,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
      // This pragma returns a row; Android's execSQL rejects that, so query it.
      await db.rawQuery('PRAGMA busy_timeout = 5000');
    },
    onCreate: (db, version) async {
      for (final statement in [
        ..._schema,
        ...passageSchemaStatements,
        ...importSchemaStatements,
      ]) {
        await db.execute(statement);
      }
      await db.insert('settings', {
        'id': 1,
        'daily_new_limit': 10,
        'timezone': 'Asia/Ho_Chi_Minh',
        'device_id': const Uuid().v4(),
      });
      await db.insert('decks', {
        'id': const Uuid().v4(),
        'deck_key': 'daily',
        'name': 'Từ vựng hằng ngày',
        'archived': 0,
      });
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        for (final statement in passageSchemaStatements) {
          await db.execute(statement);
        }
      }
      if (oldVersion < 3) {
        for (final statement in importSchemaStatements) {
          await db.execute(statement);
        }
      }
    },
    // Future migrations must be explicit. Never delete a newer database.
    onDowngrade: (db, oldVersion, newVersion) async =>
        throw StateError('Database version is newer than this app.'),
  ),
);

const _schema = [
  '''CREATE TABLE settings (
    id INTEGER PRIMARY KEY CHECK(id = 1),
    daily_new_limit INTEGER NOT NULL CHECK(daily_new_limit BETWEEN 0 AND 100),
    timezone TEXT NOT NULL, device_id TEXT NOT NULL)''',
  '''CREATE TABLE decks (
    id TEXT PRIMARY KEY, deck_key TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0)''',
  '''CREATE TABLE entries (
    id TEXT PRIMARY KEY, term TEXT NOT NULL, normalized_term TEXT NOT NULL,
    source_language TEXT NOT NULL DEFAULT 'en',
    target_language TEXT NOT NULL DEFAULT 'vi',
    created_at INTEGER NOT NULL,
    UNIQUE(normalized_term, source_language, target_language))''',
  '''CREATE TABLE senses (
    id TEXT PRIMARY KEY, entry_id TEXT NOT NULL REFERENCES entries(id),
    sense_key TEXT NOT NULL, meaning TEXT NOT NULL DEFAULT '',
    search_text TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('draft','approved')),
    content_revision INTEGER NOT NULL DEFAULT 1,
    CHECK(status != 'approved' OR length(trim(meaning)) > 0),
    UNIQUE(entry_id, sense_key))''',
  '''CREATE TABLE deck_entries (
    deck_id TEXT NOT NULL REFERENCES decks(id),
    entry_id TEXT NOT NULL REFERENCES entries(id),
    PRIMARY KEY(deck_id, entry_id))''',
  '''CREATE TABLE cards (
    id TEXT PRIMARY KEY, sense_id TEXT NOT NULL UNIQUE REFERENCES senses(id),
    state TEXT NOT NULL DEFAULT 'new' CHECK(state IN ('new','review','relearning')),
    due_at INTEGER, interval_days INTEGER NOT NULL DEFAULT 1,
    lapses INTEGER NOT NULL DEFAULT 0, revision INTEGER NOT NULL DEFAULT 0,
    suspended INTEGER NOT NULL DEFAULT 0,
    scheduler_version INTEGER NOT NULL DEFAULT 1,
    last_review_id TEXT)''',
  '''CREATE TABLE review_events (
    id TEXT PRIMARY KEY, card_id TEXT NOT NULL REFERENCES cards(id),
    rating TEXT NOT NULL, reviewed_at INTEGER NOT NULL, study_day TEXT NOT NULL,
    was_new INTEGER NOT NULL, device_id TEXT NOT NULL,
    content_revision INTEGER NOT NULL, scheduler_version INTEGER NOT NULL,
    previous_state TEXT NOT NULL, new_state TEXT NOT NULL,
    previous_interval INTEGER NOT NULL, new_interval INTEGER NOT NULL,
    previous_due INTEGER, new_due INTEGER NOT NULL)''',
  'CREATE INDEX cards_due ON cards(suspended, state, due_at)',
  'CREATE INDEX reviews_day ON review_events(study_day, was_new)',
  'CREATE INDEX deck_entries_entry ON deck_entries(entry_id)',
];

const passageSchemaStatements = [
  """CREATE TABLE passage_jobs (
    id TEXT PRIMARY KEY, source_text TEXT NOT NULL,
    min_level TEXT NOT NULL CHECK(min_level IN ('A1','A2','B1','B2','C1','C2')),
    max_items INTEGER NOT NULL CHECK(max_items BETWEEN 1 AND 100),
    cache_key TEXT NOT NULL, created_at INTEGER NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('pending','complete','error','cancelled')),
    result_json TEXT, provider TEXT, model TEXT,
    removed INTEGER NOT NULL DEFAULT 0, at_limit INTEGER NOT NULL DEFAULT 0,
    attempts_json TEXT NOT NULL DEFAULT '[]', error_text TEXT)""",
  """CREATE TABLE sense_origins (
    id TEXT PRIMARY KEY, sense_id TEXT NOT NULL REFERENCES senses(id),
    job_id TEXT REFERENCES passage_jobs(id) ON DELETE SET NULL,
    estimated_level TEXT NOT NULL CHECK(estimated_level IN ('A1','A2','B1','B2','C1','C2')),
    level_source TEXT NOT NULL CHECK(level_source IN ('llm','user')),
    provider TEXT NOT NULL, model TEXT NOT NULL, created_at INTEGER NOT NULL,
    UNIQUE(sense_id, job_id))""",
  'CREATE INDEX passage_cache ON passage_jobs(cache_key, created_at)',
];

const importSchemaStatements = [
  'ALTER TABLE senses ADD COLUMN part_of_speech TEXT',
  'ALTER TABLE senses ADD COLUMN pronunciation TEXT',
  'ALTER TABLE senses ADD COLUMN note TEXT',
  """CREATE TABLE import_batches (
    id TEXT PRIMARY KEY, source_name TEXT NOT NULL, source_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL, selected_rows INTEGER NOT NULL,
    new_senses INTEGER NOT NULL, memberships INTEGER NOT NULL,
    approved INTEGER NOT NULL, skipped INTEGER NOT NULL)""",
];
