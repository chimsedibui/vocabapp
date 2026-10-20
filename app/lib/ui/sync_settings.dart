import 'package:flutter/material.dart';

import '../services/sync_service.dart';
import 'editors.dart';

String syncStatusText(SyncService sync) {
  if (!sync.configured) return 'Chưa bật. Thư viện chỉ lưu trên thiết bị này.';
  if (sync.running) return 'Đang đồng bộ…';
  final waiting = sync.pending == 0
      ? ''
      : ' · ${sync.pending} thay đổi chờ gửi';
  if (sync.lastError != null) return '${sync.lastError}$waiting';
  final last = sync.lastSuccess;
  if (last == null) return 'Chưa đồng bộ lần nào$waiting';
  final t = last.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Đồng bộ lúc ${two(t.hour)}:${two(t.minute)}$waiting';
}

/// App-bar indicator; tap to sync now.
class SyncStatusButton extends StatelessWidget {
  const SyncStatusButton({super.key, required this.sync});
  final SyncService sync;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) {
      if (!sync.configured) return const SizedBox.shrink();
      final icon = sync.running
          ? Icons.cloud_sync_outlined
          : sync.lastError != null
          ? Icons.cloud_off_outlined
          : sync.pending > 0
          ? Icons.cloud_upload_outlined
          : Icons.cloud_done_outlined;
      return IconButton(
        tooltip: syncStatusText(sync),
        onPressed: sync.running ? null : sync.sync,
        icon: Icon(
          icon,
          color: sync.lastError != null
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      );
    },
  );
}

class SyncSettings extends StatelessWidget {
  const SyncSettings({super.key, required this.sync});
  final SyncService sync;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ListenableBuilder(
        listenable: sync,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Đồng bộ máy tính ↔ điện thoại',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              syncStatusText(sync),
              style: sync.lastError == null
                  ? null
                  : TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
            const Text(
              'Qua Cloudflare Worker của bạn. Học offline vẫn ghi trên máy; thay đổi được gửi khi có mạng.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (sync.configured)
                  FilledButton.tonalIcon(
                    onPressed: sync.running ? null : sync.sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Đồng bộ ngay'),
                  ),
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SyncSettingsPage(sync: sync),
                    ),
                  ),
                  child: Text(sync.configured ? 'Cấu hình' : 'Bật đồng bộ'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({
    super.key,
    required this.sync,
    this.store = const SyncConfigStore(),
  });
  final SyncService sync;
  final SyncConfigStore store;
  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  final _url = TextEditingController(), _token = TextEditingController();
  bool _busy = true, _saved = false;
  String? _message;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await widget.store.load();
      if (config != null) {
        _url.text = config.url;
        _token.text = config.token;
        _saved = true;
      }
    } catch (e) {
      _message = friendlyError(e);
      _error = true;
    }
    if (mounted) setState(() => _busy = false);
  }

  SyncConfig get _config =>
      SyncConfig(url: _url.text.trim(), token: _token.text.trim());

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await action();
      _error = false;
      _message = message;
    } catch (e) {
      _error = true;
      _message = friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đồng bộ')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Nhập địa chỉ Worker và mã đồng bộ (SYNC_TOKEN) đã tạo khi deploy theo server/sync-worker/README.md. Dùng cùng cấu hình trên máy tính và điện thoại. Mã lưu trong kho bảo mật của thiết bị, không nằm trong file sao lưu.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ Worker',
                hintText: 'https://vocabapp-sync.ten.workers.dev',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _token,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Mã đồng bộ'),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await widget.sync.test(_config);
                          await widget.store.save(_config);
                          _saved = true;
                          await widget.sync.sync();
                          return widget.sync.lastError ??
                              'Đã lưu và đồng bộ. Làm tương tự trên thiết bị còn lại.';
                        }),
                  child: const Text('Kiểm tra và lưu'),
                ),
                if (_saved)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await widget.store.clear();
                            _saved = false;
                            _url.clear();
                            _token.clear();
                            await widget.sync.sync();
                            return 'Đã tắt đồng bộ trên thiết bị này. Dữ liệu vẫn giữ nguyên.';
                          }),
                    child: const Text('Tắt đồng bộ trên thiết bị này'),
                  ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _message!,
                  style: _error
                      ? TextStyle(color: Theme.of(context).colorScheme.error)
                      : null,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
