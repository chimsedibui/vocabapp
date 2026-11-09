import 'package:flutter/material.dart';

import '../services/word_notifications.dart';

class NotificationSettings extends StatefulWidget {
  const NotificationSettings({super.key});
  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings>
    with WidgetsBindingObserver {
  bool _enabled = false, _allowed = true, _busy = true;
  int _interval = 15;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The notification's "Tắt" button or system settings may change it outside the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final s = await WordNotifications.status();
      if (!mounted) return;
      setState(() {
        _enabled = s.enabled;
        _interval = s.interval;
        _allowed = s.allowed;
      });
    } catch (_) {
      /* Leaves the switch off. */
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(bool on, int interval) async {
    setState(() => _busy = true);
    try {
      if (on) {
        final ok = await WordNotifications.enable(interval);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Chưa được phép hiện thông báo. Hãy bật trong Cài đặt Android của VocabApp.',
              ),
            ),
          );
        }
      } else {
        await WordNotifications.disable();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không đổi được cài đặt thông báo.')),
        );
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thông báo từ vựng',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Ghim một từ bạn đánh giá Quên/Khó/Tạm lên màn hình khóa và thanh thông báo, kèm phiên âm, nghĩa và ví dụ. Từ đổi khi bạn bật màn hình, không tự đánh thức máy nên rất ít tốn pin.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled && _allowed,
            title: const Text('Ghim từ khó lên màn hình khóa'),
            subtitle: _enabled && !_allowed
                ? Text(
                    'Thông báo đang bị tắt trong Cài đặt Android.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : null,
            onChanged: _busy ? null : (v) => _apply(v, _interval),
          ),
          DropdownButtonFormField<int>(
            initialValue: _interval,
            key: ValueKey(_interval),
            decoration: const InputDecoration(
              labelText: 'Đổi từ khi bật màn hình, cách lần trước ít nhất',
            ),
            items: [
              for (final m in WordNotifications.intervals)
                DropdownMenuItem(value: m, child: Text('$m phút')),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    if (v == null) return;
                    if (_enabled) {
                      _apply(true, v);
                    } else {
                      setState(() => _interval = v);
                    }
                  },
          ),
          const SizedBox(height: 12),
          Text(
            'Máy OPPO/OnePlus/Realme (ColorOS) và một số hãng khác chặn app chạy nền: hãy bật "Tự khởi động" và "Cho phép hoạt động nền" cho VocabApp, nếu không từ chỉ hiện lại sau khi bạn mở app (ví dụ sau khi khởi động lại máy).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton.icon(
            onPressed: () =>
                WordNotifications.openAppSettings().catchError((_) {
                  /* No settings screen on this device. */
                }),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Mở cài đặt ứng dụng'),
          ),
        ],
      ),
    ),
  );
}
