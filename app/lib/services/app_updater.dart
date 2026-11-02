import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/models.dart';
import 'release_service.dart';

/// In-app update: downloads the platform package of a GitHub release, checks
/// it against the `.sha256` file published next to it, then hands it to the
/// OS installer.
///
/// - Android: the APK goes through `PackageInstaller` (`MainActivity.kt`,
///   channel `vocabapp/update`); on Android 12+ it installs without a
///   confirm dialog (the app closes and must be reopened); older versions ask.
/// - Windows: `Setup.exe` starts silently, waits for the app to quit and
///   reopens it when done (`installer/VocabApp.iss`); its log is written next
///   to the download as `setup.log`.
class AppUpdater {
  AppUpdater({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _channel = MethodChannel('vocabapp/update');
  static const maxBytes = 300 * 1024 * 1024;

  static bool get supported => Platform.isAndroid || Platform.isWindows;

  /// Release asset installed on this platform (see `scripts/ci/package.py`).
  static String? assetName(String version, {String? os}) =>
      switch (os ?? Platform.operatingSystem) {
        'android' => 'VocabApp-$version-android-arm64.apk',
        'windows' => 'VocabApp-$version-Setup.exe',
        _ => null,
      };

  /// Downloads into [dir] and returns the verified file.
  Future<File> download(
    AppRelease release,
    Directory dir, {
    String? os,
    void Function(double progress)? onProgress,
  }) async {
    final name = assetName(release.version, os: os);
    final url = release.assets[name],
        checksumUrl = release.assets['$name.sha256'];
    if (name == null || url == null || checksumUrl == null) {
      throw const UserFacingException(
        'Bản phát hành này chưa có gói cài cho thiết bị. Hãy mở trang phát hành.',
      );
    }
    final target = File(p.join(dir.path, name));
    final part = File('${target.path}.part');
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final checksum = await _client
          .get(checksumUrl)
          .timeout(const Duration(seconds: 20));
      final expected = RegExp(r'^[0-9a-f]{64}')
          .firstMatch(checksum.body.trim().toLowerCase())
          ?.group(0);
      if (checksum.statusCode != 200 || expected == null) {
        throw const FormatException();
      }
      final response = await _client.send(http.Request('GET', url));
      final total = response.contentLength;
      if (response.statusCode != 200 || (total ?? 0) > maxBytes) {
        throw const FormatException();
      }
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 60),
        )) {
          received += chunk.length;
          if (received > maxBytes) throw const FormatException();
          sink.add(chunk);
          if (total != null && total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      final actual = (await sha256.bind(part.openRead()).first).toString();
      if (actual != expected) {
        await part.delete();
        throw const UserFacingException(
          'File tải về không khớp mã kiểm tra nên đã bị bỏ. Hãy thử lại.',
        );
      }
      return await part.rename(target.path);
    } on UserFacingException {
      rethrow;
    } catch (_) {
      throw const UserFacingException(
        'Chưa tải được bản mới. Hãy thử lại khi có mạng hoặc mở trang phát hành.',
      );
    }
  }

  /// Starts the installer. On Windows [quit] must close the app so Setup can
  /// replace its files.
  Future<void> install(
    File file, {
    required Future<void> Function() quit,
  }) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('installApk', {'path': file.path});
      return;
    }
    // Started directly: a detached powershell.exe gets no console and exits
    // without running its command, so the old Wait-Process wrapper never ran.
    await Process.start(file.path, [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/LOG=${p.join(file.parent.path, 'setup.log')}',
    ], mode: ProcessStartMode.detached);
    await quit();
  }

  void close() => _client.close();
}
