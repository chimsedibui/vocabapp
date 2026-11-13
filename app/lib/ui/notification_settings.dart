import 'package:flutter/material.dart';

import '../services/word_notifications.dart';

class NotificationSettings extends StatefulWidget {
  const NotificationSettings({super.key});
  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings>
    with WidgetsBindingObserver {
  bool _enabled = false, _allowed = true, _keepAlive = false, _busy = true;
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
        _interval = WordNotifications.intervals.contains(s.interval)
            ? s.interval
            : 15;
        _allowed = s.allowed;
        _keepAlive = s.keepAlive;
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

  Future<void> _openSettings(Future<void> Function() open) async {
    try {
      await open();
    } catch (_) {
      /* No settings screen on this device. */
    }
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled && _allowed,
            title: const Text('Ghim từ khó'),
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
            decoration: const InputDecoration(labelText: 'Đổi từ sau ít nhất'),
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
          if (_enabled && _allowed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _keepAlive ? Icons.lock_clock : Icons.lock_clock_outlined,
              ),
              title: const Text('Giữ từ trên màn hình khóa'),
              subtitle: _keepAlive
                  ? null
                  : const Text('Cần trên OPPO/OnePlus/Realme'),
              trailing: _keepAlive
                  ? const Icon(Icons.check)
                  : FilledButton.tonal(
                      onPressed: () => _openSettings(
                        WordNotifications.openKeepAliveSettings,
                      ),
                      child: const Text('Bật'),
                    ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () =>
                    _openSettings(WordNotifications.openNotificationSettings),
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('Cài đặt thông báo'),
              ),
              TextButton.icon(
                onPressed: () =>
                    _openSettings(WordNotifications.openAppSettings),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Cài đặt ứng dụng'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
