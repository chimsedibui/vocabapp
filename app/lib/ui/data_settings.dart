import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/library_repository.dart';
import '../domain/models.dart';
import '../services/backup_service.dart';
import '../services/release_service.dart';
import 'editors.dart';

class DataSettings extends StatefulWidget {
  const DataSettings({
    super.key,
    required this.repository,
    required this.onRestored,
  });
  final LibraryRepository repository;
  final VoidCallback onRestored;
  @override
  State<DataSettings> createState() => _DataSettingsState();
}

class _DataSettingsState extends State<DataSettings> {
  final _releases = ReleaseService();
  String? _version;
  String? _message;
  bool _busy = false;
  AppRelease? _release;
  @override
  void initState() {
    super.initState();
    _loadVersion();
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
    return 'Đã sao lưu từ, nhóm và toàn bộ tiến độ học.';
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
    final bytes = builder.takeBytes();
    final service = BackupService(widget.repository.db);
    final summary = service.inspect(bytes);
    if (!mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thay thế toàn bộ thư viện?'),
        content: Text(
          'Bản sao có ${summary.entries} từ, ${summary.senses} nghĩa và ${summary.reviews} lượt ôn.\n\nThư viện hiện tại sẽ được thay thế. App giữ thêm một bản phục hồi trên thiết bị trước khi khôi phục.',
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

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
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
                'File sao lưu giữ toàn bộ từ và tiến độ. Khôi phục thay thế thư viện hiện tại; không tự gộp hai thiết bị.',
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
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
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
                'Bản mới được phát hành trên GitHub. Chỉ kiểm tra khi bạn chọn; phiên học offline vẫn hoạt động bình thường.',
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
                                : 'Có bản ${release.version}. Mở trang phát hành để xem thay đổi và tải APK hoặc bản Windows.';
                          }),
                    child: const Text('Kiểm tra bản mới'),
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
        const Padding(
          padding: EdgeInsets.all(12),
          child: LinearProgressIndicator(),
        ),
      if (_message != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
    ],
  );
}
