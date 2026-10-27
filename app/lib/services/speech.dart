import 'package:flutter/services.dart';

/// Reads English text aloud with the device's built-in voice: SAPI on
/// Windows (`windows/runner/flutter_window.cpp`), TextToSpeech on Android
/// (`MainActivity.kt`). Offline and free; no audio is downloaded.
class Speech {
  static const _channel = MethodChannel('vocabapp/speech');

  /// False when the platform has no voice or no implementation (tests).
  static Future<bool> speak(String text) async {
    try {
      return await _channel.invokeMethod<bool>('speak', {'text': text}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
