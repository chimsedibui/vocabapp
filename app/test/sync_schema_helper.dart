import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Removes the v5 history and v4 sync schema so a test can simulate an
/// older database.
Future<void> dropSyncSchema(Database db) async {
  for (final t in await db.query(
    'sqlite_master',
    where: "type='trigger' AND (name LIKE 'sync_%' OR name LIKE 'history_%')",
  )) {
    await db.execute('DROP TRIGGER ${t['name']}');
  }
  await db.execute('DROP TABLE sense_history');
  await db.execute('DROP TABLE sync_outbox');
  await db.execute('DROP TABLE sync_meta');
}
