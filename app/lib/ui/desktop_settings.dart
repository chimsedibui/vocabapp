import 'package:flutter/material.dart';

import '../services/desktop_shell.dart';

class DesktopSettings extends StatelessWidget {
  const DesktopSettings({super.key, required this.shell});
  final DesktopShell shell;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: shell,
    builder: (context, _) => Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chạy nền trên Windows',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Bấm X để thu xuống khay hệ thống. Thoát hẳn bằng chuột phải vào biểu tượng VocabApp ở khay.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: shell.autostart,
              title: const Text('Mở cùng Windows'),
              subtitle: const Text('Khởi động ẩn dưới khay khi đăng nhập.'),
              onChanged: (v) async {
                try {
                  await shell.setAutostart(v);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Không ghi được cài đặt khởi động.'),
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: shell.hotkey,
              decoration: const InputDecoration(
                labelText: 'Phím tắt tra chữ đang bôi đen',
              ),
              items: [
                for (final key in DesktopShell.keys)
                  DropdownMenuItem(value: key, child: Text('Ctrl+Alt+$key')),
              ],
              onChanged: (v) {
                if (v != null) shell.setHotkey(v);
              },
            ),
            const SizedBox(height: 8),
            Text(
              shell.hotkeyActive
                  ? 'Bôi đen chữ ở bất kỳ app nào rồi nhấn ${shell.shortcut}: popup hiện nghĩa và nút thêm vào nhóm.'
                  : '${shell.shortcut} đang bị app khác dùng. Hãy chọn phím khác.',
              style: shell.hotkeyActive
                  ? null
                  : TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
    ),
  );
}
