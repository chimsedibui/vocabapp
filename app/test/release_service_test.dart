import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocabapp/domain/models.dart';
import 'package:vocabapp/services/release_service.dart';

void main() {
  test('numeric versions, pre-releases and downgrade protection', () {
    expect(ReleaseService.newer('v0.10.0', '0.9.1'), true);
    expect(ReleaseService.newer('v0.2.0', '0.2.0'), false);
    expect(ReleaseService.newer('v0.1.0', '0.2.0'), false);
    expect(ReleaseService.newer('v0.3.0-beta', '0.2.0'), false);
  });
  test(
    'only accepts release and download URLs from the configured repository',
    () async {
      final service = ReleaseService(
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://github.com/chimsedibui/vocabapp/releases/latest/download/release.json',
          );
          return http.Response(
            jsonEncode({
              'version': '0.3.0',
              'assets': {
                'android-arm64': {
                  'name': 'app.apk',
                  'url': 'https://github.com/chimsedibui/vocabapp/releases/download/v0.3.0/app.apk',
                },
                'windows-x64': {
                  'name': 'bad.zip',
                  'url': 'https://untrusted.example/bad.zip',
                },
              },
            }),
            200,
          );
        }),
      );
      final release = await service.latest('0.2.0');
      expect(release!.version, '0.3.0');
      expect(release.assets.keys, ['app.apk', 'app.apk.sha256']);
      expect(
        release.page.toString(),
        'https://github.com/chimsedibui/vocabapp/releases/tag/v0.3.0',
      );
      service.close();
    },
  );
  test('404 is no release; connectivity error is actionable', () async {
    final missing = ReleaseService(
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(await missing.latest('0.2.0'), isNull);
    missing.close();
    final broken = ReleaseService(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      broken.latest('0.2.0'),
      throwsA(isA<UserFacingException>()),
    );
    broken.close();
    final limited = ReleaseService(
      client: MockClient(
        (_) async =>
            http.Response('', 403, headers: {'x-ratelimit-remaining': '0'}),
      ),
    );
    await expectLater(limited.latest('0.2.0'), throwsA(isA<RateLimited>()));
    limited.close();
  });
}
