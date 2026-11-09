import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'ids.dart';

DatabaseFactory get appDatabaseFactory => Platform.isAndroid || Platform.isIOS
    ? mobile.databaseFactory
    : databaseFactoryFfi;

/// Current DB version; also sent to the sync Worker so it can send an older
/// app only the columns that app knows.
const dbSchemaVersion = 6;

Future<Database> openAppDatabase() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return openVocabularyDatabase(
    appDatabaseFactory,
    p.join(dir.path, 'vocabulary.db'),
  );
}

Future<Database> openVocabularyDatabase(
  DatabaseFactory factory,
  String path, {
  bool singleInstance = true,
}) => factory.openDatabase(
  path,
  options: OpenDatabaseOptions(
    singleInstance: singleInstance,
    version: dbSchemaVersion,
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
        ...syncSchemaStatements,
        ...historySchemaStatements,
        ...timingSchemaStatements,
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
        'id': Ids.deck('daily'),
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
      if (oldVersion < 4) {
        // Before the triggers exist, so the one-off rewrite is not queued;
        // first sync seeds every row anyway.
        await Ids.normalize(db);
        for (final statement in syncSchemaStatements) {
          await db.execute(statement);
        }
      }
      if (oldVersion < 5) {
        for (final statement in historySchemaStatements) {
          await db.execute(statement);
        }
      }
      if (oldVersion < 6) {
        for (final statement in timingSchemaStatements) {
          await db.execute(statement);
        }
        // While this device ran an older app the Worker sent it reviews
        // without timing; pull everything once more to get it back.
        if (oldVersion >= 4) {
          await db.execute("UPDATE sync_meta SET value='0' WHERE key='cursor'");
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

/// Learning analytics (docs/15). A session is the reviews sharing a
/// `session_id`; `shown_at`/`flipped_at` time each card. Null on reviews made
/// before DB v6.
const timingSchemaStatements = [
  'ALTER TABLE review_events ADD COLUMN session_id TEXT',
  'ALTER TABLE review_events ADD COLUMN shown_at INTEGER',
  'ALTER TABLE review_events ADD COLUMN flipped_at INTEGER',
];

/// Tables replicated by sync, parents first. `settings` stays per device.
const syncTables = {
  'decks': ['id'],
  'entries': ['id'],
  'senses': ['id'],
  'deck_entries': ['deck_id', 'entry_id'],
  'cards': ['id'],
  'review_events': ['id'],
  'passage_jobs': ['id'],
  'sense_origins': ['id'],
  'import_batches': ['id'],
  'sense_history': ['id'],
};

String syncPkSql(String table, String row) =>
    syncTables[table]!.map((c) => '$row.$c').join(" || '|' || ");

final syncSchemaStatements = [
  // One row per changed record; the current row is read at push time and a
  // missing row becomes a tombstone. Triggers delete+insert rather than
  // INSERT OR REPLACE, which is ignored for writes caused by FK actions.
  """CREATE TABLE sync_outbox (
    tbl TEXT NOT NULL, pk TEXT NOT NULL, changed_at INTEGER NOT NULL,
    PRIMARY KEY(tbl, pk)) WITHOUT ROWID""",
  'CREATE TABLE sync_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  // Tables that existed at DB version 4; later tables add their own triggers.
  for (final table in syncTables.keys.take(9)) ..._syncTriggers(table),
];

List<String> _syncTriggers(String table) => [
  for (final (event, rows) in [
    ('INSERT', ['NEW']),
    ('UPDATE', ['OLD', 'NEW']),
    ('DELETE', ['OLD']),
  ])
    """CREATE TRIGGER sync_${table}_${event.toLowerCase()}
      AFTER $event ON $table
      WHEN (SELECT value FROM sync_meta WHERE key='applying') IS NOT '1'
      BEGIN
        ${rows.map((r) => "DELETE FROM sync_outbox WHERE tbl='$table' AND pk=${syncPkSql(table, r)}; INSERT INTO sync_outbox VALUES('$table', ${syncPkSql(table, r)}, $_nowMs);").join('\n        ')}
      END""",
];

/// Closes the current version of a sense into history under a given id
/// (params: history id, sense id); the caller queues it for sync. Used when a newer remote edit replaces an unsynced local one, which
/// the triggers skip while applying.
const keepLosingSenseSql = '''INSERT INTO sense_history SELECT ?, s.id,
    s.entry_id, s.meaning, s.part_of_speech, s.pronunciation, s.note, s.status,
    s.content_revision,
    coalesce((SELECT max(valid_to) FROM sense_history h WHERE h.sense_id=s.id),
      (SELECT created_at FROM entries WHERE id=s.entry_id)),
    $_nowMs, 'update' FROM senses s WHERE s.id=?''';

const _nowMs = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";

/// SCD Type 2 for senses: every edit or delete closes the previous version
/// into `sense_history` (valid_from..valid_to); the live row is the open
/// version. Rows applied from sync are skipped, because the editing device
/// already recorded and synced the version. Restore sets `history_off`.
final historySchemaStatements = [
  """CREATE TABLE sense_history (
    id TEXT PRIMARY KEY, sense_id TEXT NOT NULL, entry_id TEXT NOT NULL,
    meaning TEXT NOT NULL, part_of_speech TEXT, pronunciation TEXT, note TEXT,
    status TEXT NOT NULL, content_revision INTEGER NOT NULL,
    valid_from INTEGER, valid_to INTEGER NOT NULL,
    change TEXT NOT NULL CHECK(change IN ('update','delete')))""",
  'CREATE INDEX sense_history_sense ON sense_history(sense_id, valid_to)',
  ..._syncTriggers('sense_history'),
  for (final (event, changed) in [
    (
      'UPDATE OF meaning, part_of_speech, pronunciation, note, status',
      'AND (OLD.meaning IS NOT NEW.meaning OR OLD.part_of_speech IS NOT NEW.part_of_speech '
          'OR OLD.pronunciation IS NOT NEW.pronunciation OR OLD.note IS NOT NEW.note '
          'OR OLD.status IS NOT NEW.status)',
    ),
    ('DELETE', ''),
  ])
    """CREATE TRIGGER history_senses_${event.split(' ').first.toLowerCase()}
      AFTER $event ON senses
      WHEN (SELECT value FROM sync_meta WHERE key='applying') IS NOT '1'
        AND (SELECT value FROM sync_meta WHERE key='history_off') IS NOT '1'
        $changed
      BEGIN
        INSERT INTO sense_history VALUES(
          lower(hex(randomblob(16))), OLD.id, OLD.entry_id, OLD.meaning,
          OLD.part_of_speech, OLD.pronunciation, OLD.note, OLD.status,
          OLD.content_revision,
          coalesce(
            (SELECT max(valid_to) FROM sense_history WHERE sense_id=OLD.id),
            (SELECT created_at FROM entries WHERE id=OLD.entry_id)),
          $_nowMs, '${event == 'DELETE' ? 'delete' : 'update'}');
      END""",
];
