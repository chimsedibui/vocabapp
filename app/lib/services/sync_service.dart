import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart' as sql_utils;

import '../data/database.dart';
import '../domain/models.dart';

/// Connection to the single-user sync Worker (see `server/README.md`).
class SyncConfig {
  const SyncConfig({required this.url, required this.token});
  final String url, token;

  Uri endpoint(String path, [Map<String, String>? query]) {
    final base = Uri.parse(url.endsWith('/') ? url : '$url/');
    return base.resolve(path).replace(queryParameters: query);
  }

  void validate() {
    final uri = Uri.tryParse(url.trim());
    final local =
        uri != null &&
        ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host);
    if (uri == null ||
        !(uri.scheme == 'https' || (uri.scheme == 'http' && local)) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const UserFacingException(
        'Địa chỉ đồng bộ cần dạng https://ten.tai-khoan.workers.dev',
      );
    }
    if (token.length < 24 ||
        token.length > 512 ||
        token.contains(RegExp(r'\s'))) {
      throw const UserFacingException(
        'Mã đồng bộ cần ít nhất 24 ký tự, không có khoảng trắng.',
      );
    }
  }

  Map<String, String> toJson() => {'url': url, 'token': token};
  factory SyncConfig.fromJson(Map<String, dynamic> json) =>
      SyncConfig(url: json['url'] as String, token: json['token'] as String);
}

class SyncConfigStore {
  const SyncConfigStore({this.storage = const FlutterSecureStorage()});
  final FlutterSecureStorage storage;
  static const _key = 'vocabapp.sync.v1';

  Future<SyncConfig?> load() async {
    try {
      final value = await storage.read(key: _key);
      return value == null
          ? null
          : SyncConfig.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      throw const UserFacingException(
        'Không đọc được cấu hình đồng bộ trong kho bảo mật. Hãy cấu hình lại.',
      );
    }
  }

  Future<void> save(SyncConfig value) async {
    value.validate();
    try {
      await storage.write(key: _key, value: jsonEncode(value.toJson()));
    } catch (_) {
      throw const UserFacingException(
        'Không lưu được cấu hình đồng bộ vào kho bảo mật.',
      );
    }
  }

  Future<void> clear() async {
    try {
      await storage.delete(key: _key);
    } catch (_) {
      throw const UserFacingException('Không xóa được cấu hình đồng bộ.');
    }
  }
}

class SyncSummary {
  const SyncSummary(this.pulled, this.pushed);
  final int pulled, pushed;
}

/// Local-first replication through a dumb row store.
///
/// SQLite triggers queue every changed row in `sync_outbox`. A sync pulls
/// rows other devices pushed after the saved cursor and applies them in one
/// transaction (a newer local edit of the same row wins), then pushes the
/// queue. Conflicts resolve per row by last write (`changed_at`), and review
/// events never conflict because each has its own ID. When the server is
/// unreachable or out of quota nothing is lost: the queue stays on the device
/// and the next sync resends it.
class SyncService extends ChangeNotifier {
  SyncService(
    this.db, {
    Future<SyncConfig?> Function()? loadConfig,
    http.Client? client,
    DateTime Function()? clock,
  }) : _loadConfig = loadConfig ?? const SyncConfigStore().load,
       _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final Database db;
  final Future<SyncConfig?> Function() _loadConfig;
  final http.Client _client;
  final DateTime Function() _clock;

  static const protocol = '1';
  static const _pageSize = 500;
  static const _maxChunkBytes = 256 * 1024;
  static const _timeout = Duration(seconds: 30);

  bool configured = false;
  bool running = false;
  DateTime? lastSuccess;
  String? lastError;
  int pending = 0;

  /// Bumped whenever remote rows were applied, so screens can reload.
  int remoteVersion = 0;

  Future<void>? _current;
  Timer? _debounce, _periodic;

  /// Starts background syncing: now, every [interval], and on [requestSync].
  void start({Duration interval = const Duration(minutes: 2)}) {
    _periodic?.cancel();
    _periodic = Timer.periodic(interval, (_) => sync());
    unawaited(sync());
  }

  /// Coalesces bursts of local edits into one sync a few seconds later.
  void requestSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), () => sync());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    _client.close();
    super.dispose();
  }

  /// Runs one sync; concurrent callers share the run in progress.
  Future<void> sync() =>
      _current ??= _run().whenComplete(() => _current = null);

  Future<void> _run() async {
    SyncConfig? config;
    try {
      config = await _loadConfig();
    } catch (e) {
      lastError = e is UserFacingException ? e.message : '$e';
    }
    configured = config != null;
    if (config == null) {
      pending = await _pendingCount();
      notifyListeners();
      return;
    }
    running = true;
    notifyListeners();
    try {
      await runOnce(config);
      lastSuccess = _clock();
      lastError = null;
    } on UserFacingException catch (e) {
      lastError = e.message;
    } catch (_) {
      lastError = 'Không kết nối được máy chủ đồng bộ. Dữ liệu vẫn trên máy và sẽ được gửi lại sau.';
    } finally {
      running = false;
      pending = await _pendingCount();
      notifyListeners();
    }
  }

  Future<int> _pendingCount() async =>
      sql_utils.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM sync_outbox'),
      ) ??
      0;

  /// Checks URL and token without changing data.
  Future<void> test(SyncConfig config) async {
    config.validate();
    await _get(config, 'v1/status');
  }

  /// One full pull + push. Throws [UserFacingException] on server errors.
  Future<SyncSummary> runOnce(SyncConfig config) async {
    final device = (await db.query('settings')).single['device_id'] as String;
    await _prepare(config);
    final pulled = await _pull(config, device);
    final pushed = await _push(config, device);
    return SyncSummary(pulled, pushed);
  }

  Future<String?> _meta(DatabaseExecutor tx, String key) async =>
      (await tx.query(
            'sync_meta',
            where: 'key=?',
            whereArgs: [key],
          )).firstOrNull?['value']
          as String?;

  Future<void> _setMeta(DatabaseExecutor tx, String key, String value) =>
      tx.insert('sync_meta', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// On first use of a server, queue every existing row with timestamp 0 so
  /// anything already on the server wins over untouched local rows while
  /// real local edits (with real timestamps) still compete fairly.
  Future<void> _prepare(SyncConfig config) => db.transaction((tx) async {
    if (await _meta(tx, 'server') == config.url) return;
    for (final table in syncTables.keys) {
      await tx.execute(
        "INSERT OR IGNORE INTO sync_outbox SELECT '$table', ${syncPkSql(table, table)}, 0 FROM $table",
      );
    }
    await _setMeta(tx, 'cursor', '0');
    await _setMeta(tx, 'server', config.url);
  });

  Future<int> _pull(SyncConfig config, String device) async {
    var cursor = int.parse(await _meta(db, 'cursor') ?? '0');
    final rows = <Map<String, dynamic>>[];
    for (var page = 0; ; page++) {
      final body = await _get(config, 'v1/pull', {
        'after': '$cursor',
        'device': device,
        'limit': '$_pageSize',
      });
      rows.addAll((body['rows'] as List).cast<Map<String, dynamic>>());
      cursor = body['cursor'] as int;
      if (body['more'] != true) break;
      if (page > 10000) throw const FormatException('Pull did not finish');
    }
    var applied = 0;
    await db.transaction((tx) async {
      // Rows arrive in server order but a page may still reference a parent
      // that arrives later; constraints are checked once at commit.
      await tx.execute('PRAGMA defer_foreign_keys = ON');
      await _setMeta(tx, 'applying', '1');
      final columns = {
        for (final table in syncTables.keys)
          table: {
            for (final c in await tx.rawQuery('PRAGMA table_info($table)'))
              c['name'] as String,
          },
      };
      for (final row in rows) {
        if (await _apply(tx, row, columns)) applied++;
      }
      await _setMeta(tx, 'cursor', '$cursor');
      await _setMeta(tx, 'applying', '0');
    });
    if (applied > 0) remoteVersion++;
    return applied;
  }

  Future<bool> _apply(
    Transaction tx,
    Map<String, dynamic> row,
    Map<String, Set<String>> columns,
  ) async {
    final table = row['t'] as String;
    final keys = syncTables[table];
    final pk = row['p'] as String;
    final values = pk.split('|');
    if (keys == null || values.length != keys.length) {
      throw const UserFacingException(
        'Dữ liệu đồng bộ đến từ phiên bản app mới hơn. Hãy cập nhật app trên máy này.',
      );
    }
    final local = await tx.query(
      'sync_outbox',
      where: 'tbl=? AND pk=?',
      whereArgs: [table, pk],
    );
    if (local.isNotEmpty &&
        (local.single['changed_at'] as int) > (row['c'] as int)) {
      return false;
    }
    final where = keys.map((k) => '$k=?').join(' AND ');
    if (row['x'] == 1) {
      await tx.delete(table, where: where, whereArgs: values);
    } else {
      final data = jsonDecode(row['d'] as String) as Map<String, dynamic>;
      if (!columns[table]!.containsAll(data.keys) ||
          keys.indexed.any((k) => data[k.$2] != values[k.$1])) {
        throw const UserFacingException(
          'Dữ liệu đồng bộ đến từ phiên bản app mới hơn. Hãy cập nhật app trên máy này.',
        );
      }
      final names = data.keys.toList();
      final updates = names.where((n) => !keys.contains(n));
      await tx.rawInsert(
        'INSERT INTO $table(${names.join(',')}) VALUES(${List.filled(names.length, '?').join(',')}) '
        'ON CONFLICT(${keys.join(',')}) DO ${updates.isEmpty ? 'NOTHING' : 'UPDATE SET ${updates.map((n) => '$n=excluded.$n').join(',')}'}',
        [for (final n in names) data[n]],
      );
    }
    if (local.isNotEmpty) {
      await tx.delete(
        'sync_outbox',
        where: 'tbl=? AND pk=?',
        whereArgs: [table, pk],
      );
    }
    return true;
  }

  Future<int> _push(SyncConfig config, String device) async {
    // Snapshot queue and rows together so a concurrent edit stays queued.
    final (upserts, tombstones) = await db.transaction((tx) async {
      final queued = await tx.query('sync_outbox');
      final byTable = <String, Map<String, int>>{};
      for (final q in queued) {
        (byTable[q['tbl'] as String] ??= {})[q['pk'] as String] =
            q['changed_at'] as int;
      }
      final upserts = <Map<String, Object?>>[];
      final tombstones = <Map<String, Object?>>[];
      for (final (rank, table) in syncTables.keys.indexed) {
        final wanted = byTable.remove(table);
        if (wanted == null) continue;
        final found = <String, Map<String, Object?>>{};
        final keys = syncTables[table]!;
        if (keys.length == 1) {
          final ids = wanted.keys.toList();
          for (var i = 0; i < ids.length; i += 500) {
            final part = ids.sublist(i, (i + 500).clamp(0, ids.length));
            for (final r in await tx.query(
              table,
              where:
                  '${keys.single} IN (${List.filled(part.length, '?').join(',')})',
              whereArgs: part,
            )) {
              found[r[keys.single] as String] = r;
            }
          }
        } else {
          for (final r in await tx.query(table)) {
            final pk = keys.map((k) => r[k]).join('|');
            if (wanted.containsKey(pk)) found[pk] = r;
          }
        }
        for (final MapEntry(key: pk, value: changed) in wanted.entries) {
          final data = found[pk];
          (data == null ? tombstones : upserts).add({
            't': table,
            'p': pk,
            'c': changed,
            'x': data == null ? 1 : 0,
            'd': data == null ? null : jsonEncode(data),
            'rank': rank,
          });
        }
      }
      // Rows of tables no longer synced are dropped from the queue.
      for (final MapEntry(key: table, value: rows) in byTable.entries) {
        for (final pk in rows.keys) {
          await tx.delete(
            'sync_outbox',
            where: 'tbl=? AND pk=?',
            whereArgs: [table, pk],
          );
        }
      }
      return (upserts, tombstones);
    });
    // Parents before children for upserts, children before parents for
    // deletes, so the other device can apply rows in server order.
    int byRank(Map<String, Object?> a, Map<String, Object?> b) =>
        (a['rank'] as int).compareTo(b['rank'] as int) != 0
        ? (a['rank'] as int).compareTo(b['rank'] as int)
        : (a['c'] as int).compareTo(b['c'] as int);
    upserts.sort(byRank);
    tombstones.sort((a, b) => byRank(b, a));
    final ordered = [...upserts, ...tombstones];

    var sent = 0;
    var chunk = <Map<String, Object?>>[];
    var bytes = 0;
    Future<void> flush() async {
      if (chunk.isEmpty) return;
      await _post(config, 'v1/push', {
        'device': device,
        'rows': [
          for (final r in chunk)
            {
              for (final k in ['t', 'p', 'c', 'x', 'd']) k: r[k],
            },
        ],
      });
      await db.transaction((tx) async {
        for (final r in chunk) {
          await tx.delete(
            'sync_outbox',
            where: 'tbl=? AND pk=? AND changed_at=?',
            whereArgs: [r['t'], r['p'], r['c']],
          );
        }
      });
      sent += chunk.length;
      chunk = [];
      bytes = 0;
    }

    for (final row in ordered) {
      final size = ((row['d'] as String?)?.length ?? 0) + 200;
      if (chunk.isNotEmpty &&
          (bytes + size > _maxChunkBytes || chunk.length >= _pageSize)) {
        await flush();
      }
      chunk.add(row);
      bytes += size;
    }
    await flush();
    return sent;
  }

  Map<String, String> _headers(SyncConfig config) => {
    'authorization': 'Bearer ${config.token}',
    'x-sync-protocol': protocol,
    'content-type': 'application/json',
  };

  Future<Map<String, dynamic>> _get(
    SyncConfig config,
    String path, [
    Map<String, String>? query,
  ]) async => _decode(
    await _client
        .get(config.endpoint(path, query), headers: _headers(config))
        .timeout(_timeout),
  );

  Future<Map<String, dynamic>> _post(
    SyncConfig config,
    String path,
    Object body,
  ) async => _decode(
    await _client
        .post(
          config.endpoint(path),
          headers: _headers(config),
          body: jsonEncode(body),
        )
        .timeout(_timeout),
  );

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? body;
    try {
      body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    final code = body?['error'];
    if (response.statusCode == 200 && body != null && code == null) {
      return body;
    }
    throw UserFacingException(switch ((response.statusCode, code)) {
      (401, _) => 'Sai mã đồng bộ. Kiểm tra lại token trong Cài đặt.',
      (_, 'quota') => 'Cloudflare đã hết hạn mức miễn phí hôm nay. Dữ liệu vẫn an toàn trên máy và sẽ tự gửi lại sau 7:00 sáng.',
      (_, 'protocol') =>
        'Máy chủ đồng bộ và app khác phiên bản. Hãy cập nhật app hoặc Worker.',
      (404, _) => 'Không tìm thấy máy chủ đồng bộ ở địa chỉ này.',
      _ =>
        'Máy chủ đồng bộ đang lỗi (${response.statusCode}). Dữ liệu vẫn trên máy và sẽ được gửi lại sau.',
    });
  }
}
