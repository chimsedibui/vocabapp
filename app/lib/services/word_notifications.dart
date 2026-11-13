import 'dart:io';

import 'package:flutter/services.dart';

/// Android pinned word (`WordNotifications.kt`, channel `vocabapp/notify`): a
/// foreground service keeps one ongoing notification on the lock screen with a
/// word last rated Quên/Khó/Tạm (IPA, part of speech, meaning, example). The
/// word changes when the screen turns on, at most once per [intervals] minutes.
/// Runs natively, so it keeps going while the app is closed.
class WordNotifications {
  static const _channel = MethodChannel('vocabapp/notify');
  static const intervals = [10, 15, 20];

  static bool get supported => Platform.isAndroid;

  static Future<({bool enabled, int interval, bool allowed})> status() async {
    final map = await _channel.invokeMapMethod<String, Object?>('status');
    return (
      enabled: map?['enabled'] == true,
      interval: map?['interval'] as int? ?? 15,
      allowed: map?['allowed'] == true,
    );
  }

  /// Asks for the notification permission when needed; false if refused.
  static Future<bool> enable(int interval) async =>
      await _channel.invokeMethod<bool>('enable', {'interval': interval}) ??
      false;

  static Future<void> disable() => _channel.invokeMethod('disable');

  /// Opens this app's system settings page (battery, auto-launch).
  static Future<void> openAppSettings() =>
      _channel.invokeMethod('openAppSettings');

  /// Opens this app's notification settings (lock screen display, channel).
  static Future<void> openNotificationSettings() =>
      _channel.invokeMethod('openNotificationSettings');
}
