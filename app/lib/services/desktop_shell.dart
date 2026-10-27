import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Windows desktop shell implemented in `windows/runner/flutter_window.cpp`:
/// tray icon, close-to-tray, `Ctrl+Alt+key` lookup of the selected text, the
/// lookup popup near the cursor and start with Windows.
///
/// Only the hotkey letter is stored here (`desktop.json` in the app support
/// directory); the startup entry lives in the user's Run registry key.
class DesktopShell extends ChangeNotifier {
  DesktopShell(this._file);
  static const _channel = MethodChannel('vocabapp/desktop');
  static const keys = ['Q', 'W', 'E', 'D', 'X', 'Z'];
  final File _file;
  final _lookups = StreamController<String?>.broadcast();
  final _dismissed = StreamController<void>.broadcast();

  String hotkey = 'Q';

  /// False when another app already owns the shortcut.
  bool hotkeyActive = false;
  bool autostart = false;

  /// Selected text for each hotkey press; null when nothing could be copied.
  Stream<String?> get lookups => _lookups.stream;

  /// The popup lost focus or was closed by Windows (Alt+F4, tray, relaunch).
  Stream<void> get dismissed => _dismissed.stream;

  String get shortcut => 'Ctrl+Alt+$hotkey';

  Future<void> start() async {
    _channel.setMethodCallHandler(_handle);
    try {
      final saved = jsonDecode(await _file.readAsString()) as Map;
      if (keys.contains(saved['hotkey'])) hotkey = saved['hotkey'] as String;
    } catch (_) {
      /* First run or unreadable file: keep the default. */
    }
    await _strings();
    hotkeyActive = await _register(hotkey);
    autostart = await _channel.invokeMethod<bool>('getAutostart') ?? false;
    notifyListeners();
  }

  Future<void> _strings() => _channel.invokeMethod('setStrings', {
    'open': 'Mở VocabApp',
    'quit': 'Thoát VocabApp',
    'hintTitle': 'VocabApp vẫn chạy ở khay hệ thống',
    'hint':
        'Bôi đen chữ ở bất kỳ đâu rồi nhấn $shortcut để tra. Thoát bằng chuột phải vào biểu tượng.',
  });

  Future<bool> _register(String key) async =>
      await _channel.invokeMethod<bool>('setHotkey', {'key': key}) ?? false;

  Future<void> setHotkey(String key) async {
    hotkey = key;
    hotkeyActive = await _register(key);
    await _strings();
    try {
      await _file.writeAsString(jsonEncode({'hotkey': key}));
    } catch (_) {
      /* The shortcut still works for this session. */
    }
    notifyListeners();
  }

  Future<void> setAutostart(bool enabled) async {
    final ok =
        await _channel.invokeMethod<bool>('setAutostart', {
          'enabled': enabled,
        }) ??
        false;
    autostart = await _channel.invokeMethod<bool>('getAutostart') ?? false;
    notifyListeners();
    if (!ok) throw StateError('Run key not writable');
  }

  Future<void> showPopup(Size size) => _channel.invokeMethod('showPopup', {
    'width': size.width.round(),
    'height': size.height.round(),
  });

  Future<void> endPopup({bool show = false}) =>
      _channel.invokeMethod('endPopup', {'show': show});

  Future<void> quit() => _channel.invokeMethod('quit');

  Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'lookup':
        _lookups.add(call.arguments as String?);
      case 'popupClosed' || 'popupBlur':
        _dismissed.add(null);
    }
  }

  static bool get supported => !kIsWeb && Platform.isWindows;
}
