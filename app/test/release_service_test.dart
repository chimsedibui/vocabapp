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
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'tag_name': 'v0.3.0',
              'draft': false,
              'prerelease': false,
              'html_url':
                  'https://github.com/chimsedibui/vocabapp/releases/tag/v0.3.0',
              'assets': [
                {
                  'name': 'app.apk',
                  'browser_download_url': 'https://github.com/chimsedibui/vocabapp/releases/download/v0.3.0/app.apk',
                },
                {
                  'name': 'bad.apk',
                  'browser_download_url': 'https://untrusted.example/app.apk',
                },
              ],
            }),
            200,
          ),
        ),
      );
      final release = await service.latest('0.2.0');
      expect(release!.version, '0.3.0');
      expect(release.assets.keys, ['app.apk']);
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
  });
}
