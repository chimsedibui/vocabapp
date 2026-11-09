import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/analytics_repository.dart';
import '../data/database.dart';
import '../data/library_repository.dart';
import '../data/snapshots.dart';
import '../domain/models.dart';
import '../services/app_updater.dart';
import '../services/backup_service.dart';
import '../services/desktop_shell.dart';
import '../services/release_service.dart';
import 'editors.dart';

class DataSettings extends StatefulWidget {
  const DataSettings({
    super.key,
    required this.repository,
    required this.onRestored,
    this.desktop,
  });
  final LibraryRepository repository;
  final VoidCallback onRestored;
  final DesktopShell? desktop;
  @override
  State<DataSettings> createState() => _DataSettingsState();
}

class _DataSettingsState extends State<DataSettings> {
  final _releases = ReleaseService();
  final _updater = AppUpdater();
  double? _progress;
  String? _version;
  String? _message;
  bool _busy = false;
  AppRelease? _release;
  DatabaseSnapshots? _snapshots;
  List<File> _snapshotFiles = [];
  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadSnapshots();
  }

  Future<void> _loadSnapshots() async {
    try {
      final snapshots = DatabaseSnapshots(
        await getApplicationSupportDirectory(),
      );
      final files = await snapshots.list();
      if (mounted) {
        setState(() {
          _snapshots = snapshots;
          _snapshotFiles = files;
        });
      }
    } catch (_) {
      /* Widget tests have no support directory. */
    }
  }

  Future<String?> _restoreSnapshot(File file) async {
    final bytes = await _snapshots!.exportBackup(file, appDatabaseFactory);
    return _confirmRestore(
      bytes,
      'Bản tự lưu trước khi cập nhật lên ${DatabaseSnapshots.version(file)}',
    );
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      /* Widget tests and unsupported hosts may not register plugins. */
    }
  }

  @override
  void dispose() {
    _releases.close();
    _updater.close();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await action();
      if (mounted) setState(() => _message = message);
    } catch (e) {
      if (mounted) setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _export() async {
    final data = await BackupService(widget.repository.db).export();
    final path = await FilePicker.saveFile(
      dialogTitle: 'Lưu bản sao thư viện',
      fileName: 'VocabApp-${DateTime.now().millisecondsSinceEpoch}.vocabbackup',
      bytes: data,
    );
    if (path == null) return null;
    return 'Đã sao lưu từ, nhóm, passage và toàn bộ tiến độ học.';
  }

  Future<String?> _exportReviews() async {
    final csv = await widget.repository.reviewsCsv();
    // BOM so Excel opens Vietnamese text as UTF-8.
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
    final path = await FilePicker.saveFile(
      dialogTitle: 'Lưu lịch sử ôn',
      fileName: 'VocabApp-reviews-${DateTime.now().millisecondsSinceEpoch}.csv',
      bytes: bytes,
    );
    if (path == null) return null;
    return 'Đã xuất toàn bộ lượt ôn ra CSV.';
  }

  Future<String?> _restore() async {
    final pick = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['vocabbackup', 'json'],
    );
    if (pick == null) return null;
    if ((pick.lengthSync() ?? 0) > BackupService.maxBytes) {
      throw const UserFacingException('Bản sao lưu vượt giới hạn 20 MiB.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in pick.readAsByteStream()) {
      if (builder.length + chunk.length > BackupService.maxBytes) {
        throw const UserFacingException('Bản sao lưu vượt giới hạn 20 MiB.');
      }
      builder.add(chunk);
    }
    return _confirmRestore(builder.takeBytes(), 'Bản sao');
  }

  Future<String?> _confirmRestore(Uint8List bytes, String source) async {
    final service = BackupService(widget.repository.db);
    final summary = service.inspect(bytes);
    if (!mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thay thế toàn bộ thư viện?'),
        content: Text(
          '$source có ${summary.entries} từ, ${summary.senses} nghĩa và ${summary.reviews} lượt ôn, ${summary.passages} passage (có văn bản nguồn).\n\nThư viện hiện tại sẽ được thay thế. App giữ thêm một bản phục hồi trên thiết bị trước khi khôi phục.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Khôi phục'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    final dir = await getApplicationSupportDirectory();
    await service.restore(
      bytes,
      saveRecovery: (snapshot) async {
        final recovery = Directory(p.join(dir.path, 'recovery'));
        await recovery.create(recursive: true);
        final target = File(
          p.join(
            recovery.path,
            'before-restore-${DateTime.now().microsecondsSinceEpoch}.vocabbackup',
          ),
        );
        final temp = File('${target.path}.tmp');
        await temp.writeAsBytes(snapshot, flush: true);
        await temp.rename(target.path);
      },
    );
    widget.onRestored();
    return 'Đã khôi phục thư viện và lịch ôn. Bản trước khi khôi phục được giữ trong thư mục recovery của app.';
  }

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const UserFacingException(
        'Không mở được trình duyệt. Hãy mở github.com/chimsedibui/vocabapp/releases.',
      );
    }
  }

  Future<String?> _update(AppRelease release) async {
    if (Platform.isWindows) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Cập nhật lên ${release.version}?'),
          content: const Text(
            'VocabApp sẽ đóng để cài bản mới rồi tự mở lại. Thư viện được tự lưu trước khi nâng cấp.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cập nhật'),
            ),
          ],
        ),
      );
      if (confirmed != true) return null;
    }
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'update'),
    );
    try {
      final file = await _updater.download(
        release,
        dir,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      await _updater.install(
        file,
        quit: () async {
          final desktop = widget.desktop;
          desktop == null ? exit(0) : await desktop.quit();
        },
      );
    } finally {
      if (mounted) setState(() => _progress = null);
    }
    return Platform.isAndroid
        ? 'Đã tải xong bản ${release.version}. Xác nhận cài đặt trong hộp thoại của Android.'
        : null;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sao lưu và chuyển thiết bị',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'File sao lưu giữ từ, tiến độ và passage có văn bản nguồn. Không chứa API key. Khôi phục thay thế thư viện hiện tại; không tự gộp hai thiết bị.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _run(_export),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Sao lưu'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(_restore),
                    icon: const Icon(Icons.restore),
                    label: const Text('Khôi phục'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(_exportReviews),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Xuất lượt ôn (CSV)'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Bản tự lưu trước khi cập nhật',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Mỗi lần mở phiên bản mới, app tự chép thư viện trước khi nâng cấp dữ liệu. Giữ 5 bản gần nhất trên thiết bị.',
              ),
              if (_snapshotFiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Chưa có bản nào.'),
                ),
              for (final file in _snapshotFiles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.history),
                  title: Text('Trước bản ${DatabaseSnapshots.version(file)}'),
                  subtitle: Text(
                    DatabaseSnapshots.takenAt(file)
                            ?.toLocal()
                            .toString()
                            .substring(0, 16) ??
                        '',
                  ),
                  trailing: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => _restoreSnapshot(file)),
                    child: const Text('Khôi phục'),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phiên bản ${_version ?? 'đang tải…'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Bản mới được phát hành trên GitHub. Chỉ kiểm tra khi bạn chọn; có thể cập nhật ngay trong app.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.tonal(
                    onPressed: _busy || _version == null
                        ? null
                        : () => _run(() async {
                            final release = await _releases.latest(_version!);
                            if (mounted) setState(() => _release = release);
                            return release == null
                                ? 'Không có bản mới được phát hành cho phiên bản này.'
                                : AppUpdater.supported
                                ? 'Có bản ${release.version}. Chọn Cập nhật ngay để tải và cài.'
                                : 'Có bản ${release.version}. Mở trang phát hành để xem thay đổi và tải bản cài.';
                          }),
                    child: const Text('Kiểm tra bản mới'),
                  ),
                  if (_release != null && AppUpdater.supported)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() => _update(_release!)),
                      icon: const Icon(Icons.system_update_alt),
                      label: Text('Cập nhật ngay (${_release!.version})'),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _open(
                              _release?.page ?? ReleaseService.latestPage,
                            );
                            return null;
                          }),
                    child: const Text('Mở trang phát hành'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (_busy)
        Padding(
          padding: const EdgeInsets.all(12),
          child: LinearProgressIndicator(value: _progress),
        ),
      if (_message != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
    ],
  );
}
