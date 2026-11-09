import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocabapp/domain/models.dart';
import 'package:vocabapp/services/app_updater.dart';
import 'package:vocabapp/services/release_service.dart';

void main() {
  const name = 'VocabApp-0.4.0-android-arm64.apk';
  final package = utf8.encode('apk bytes');
  final release = AppRelease('0.4.0', Uri.parse('https://example.test'), {
    name: Uri.parse('https://example.test/$name'),
    '$name.sha256': Uri.parse('https://example.test/$name.sha256'),
  });
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('update'));
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  AppUpdater updater(String checksum) => AppUpdater(
    client: MockClient(
      (request) async => request.url.path.endsWith('.sha256')
          ? http.Response('$checksum  $name\n', 200)
          : http.Response.bytes(package, 200),
    ),
  );

  test('platform asset names match the release packaging', () {
    expect(AppUpdater.assetName('1.2.3', os: 'android'), contains('.apk'));
    expect(AppUpdater.assetName('1.2.3', os: 'windows'), contains('Setup.exe'));
    expect(AppUpdater.assetName('1.2.3', os: 'linux'), isNull);
  });

  test('keeps the package only when its checksum matches', () async {
    final ok = updater(sha256.convert(package).toString());
    final file = await ok.download(release, dir, os: 'android');
    expect(await file.readAsBytes(), package);
    ok.close();

    final bad = updater('0' * 64);
    await expectLater(
      bad.download(release, dir, os: 'android'),
      throwsA(isA<UserFacingException>()),
    );
    expect(dir.listSync(), isEmpty);
    bad.close();
  });

  test('GitHub rate limiting says so instead of a generic error', () async {
    final limited = AppUpdater(
      client: MockClient(
        (_) async => http.Response('', 429, headers: {'retry-after': '120'}),
      ),
    );
    await expectLater(
      limited.download(release, dir, os: 'android'),
      throwsA(
        isA<RateLimited>().having(
          (e) => e.message,
          'message',
          contains('2 phút'),
        ),
      ),
    );
    limited.close();
  });

  test('missing platform asset points to the release page', () async {
    final service = updater('');
    await expectLater(
      service.download(release, dir, os: 'windows'),
      throwsA(isA<UserFacingException>()),
    );
    service.close();
  });
}
