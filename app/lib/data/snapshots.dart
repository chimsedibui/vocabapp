import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../services/backup_service.dart';
import 'database.dart';

/// File copies of `vocabulary.db` taken the first time a new app version
/// opens it, so before any schema migration. The newest [keep] stay in
/// `<support>/snapshots`. Restoring migrates a temporary copy and goes
/// through [BackupService.restore], which validates and keeps a recovery file.
class DatabaseSnapshots {
  DatabaseSnapshots(this.directory, {this.keep = 5});
  final Directory directory;
  final int keep;
  static const _companions = ['-wal', '-shm', '-journal'];

  Directory get folder => Directory(p.join(directory.path, 'snapshots'));
  File get _database => File(p.join(directory.path, 'vocabulary.db'));
  File get _marker => File(p.join(folder.path, 'last_version'));

  /// Call before opening the database. Returns the snapshot, if one was made.
  Future<File?> beforeOpen(String appVersion) async {
    await folder.create(recursive: true);
    final last = await _marker.exists()
        ? (await _marker.readAsString()).trim()
        : null;
    if (last == appVersion) return null;
    File? target;
    if (await _database.exists()) {
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      // Sub-second digits keep the order when versions change within a second.
      target = File(
        p.join(folder.path, 'vocabulary-before-$appVersion-$stamp.db'),
      );
      await _copy(_database, target);
    }
    await _marker.writeAsString(appVersion, flush: true);
    await _prune();
    return target;
  }

  /// Newest first.
  Future<List<File>> list() async {
    if (!await folder.exists()) return [];
    final files = await folder
        .list()
        .where((e) => e is File && e.path.endsWith('.db'))
        .cast<File>()
        .toList();
    files.sort((a, b) => _stamp(b).compareTo(_stamp(a)));
    return files;
  }

  static String _stamp(File f) =>
      RegExp(r'-(\d{14,})\.db$').firstMatch(f.path)?.group(1) ?? '';

  /// "0.3.3" from `vocabulary-before-0.3.3-20261028101500.db`.
  static String version(File f) =>
      RegExp(r'before-(.+)-\d{14,}\.db$').firstMatch(f.path)?.group(1) ?? '?';

  static DateTime? takenAt(File f) {
    final s = _stamp(f);
    if (s.isEmpty) return null;
    return DateTime.utc(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
      int.parse(s.substring(8, 10)),
      int.parse(s.substring(10, 12)),
      int.parse(s.substring(12, 14)),
    );
  }

  /// Opens a temporary copy (migrated like the live library) as a backup.
  Future<Uint8List> exportBackup(File snapshot, DatabaseFactory factory) async {
    final work = Directory(p.join(folder.path, 'work'));
    if (await work.exists()) await work.delete(recursive: true);
    await work.create(recursive: true);
    final copy = File(p.join(work.path, 'snapshot.db'));
    try {
      await _copy(snapshot, copy);
      final db = await openVocabularyDatabase(
        factory,
        copy.path,
        singleInstance: false,
      );
      try {
        return await BackupService(db).export();
      } finally {
        await db.close();
      }
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<void> _copy(File source, File target) async {
    final temp = File('${target.path}.tmp');
    await source.copy(temp.path);
    for (final suffix in _companions) {
      final extra = File('${source.path}$suffix');
      if (await extra.exists()) await extra.copy('${target.path}$suffix');
    }
    await temp.rename(target.path);
  }

  Future<void> _prune() async {
    for (final old in (await list()).skip(keep)) {
      for (final suffix in ['', ..._companions]) {
        final f = File('${old.path}$suffix');
        if (await f.exists()) await f.delete();
      }
    }
  }
}
