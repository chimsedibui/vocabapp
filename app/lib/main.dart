import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'data/database.dart';
import 'data/library_repository.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  try {
    final db = await openAppDatabase();
    runApp(VocabApp(repository: LibraryRepository(db)));
  } catch (_) {
    // Do not silently reset a database that cannot be opened or migrated.
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_outlined, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Không thể mở thư viện. Dữ liệu chưa bị thay đổi.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Kiểm tra dung lượng và quyền truy cập, rồi thử lại.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: main, child: const Text('Thử lại')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
