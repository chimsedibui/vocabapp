import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';

class AppRelease {
  const AppRelease(this.version, this.page, this.assets);
  final String version;
  final Uri page;
  final Map<String, Uri> assets;
}

/// GitHub refused because of too many requests (429, or 403 with no quota left).
class RateLimited extends UserFacingException {
  const RateLimited(super.message);

  static void check(http.BaseResponse response) {
    final code = response.statusCode;
    if (code != 429 &&
        !(code == 403 && response.headers['x-ratelimit-remaining'] == '0')) {
      return;
    }
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    final wait = seconds == null
        ? 'vài phút'
        : '${(seconds / 60).ceil().clamp(1, 60)} phút';
    throw RateLimited(
      'GitHub đang giới hạn số lượt tải (quá nhiều request). Hãy thử lại sau $wait.',
    );
  }
}

class ReleaseService {
  ReleaseService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const repository = 'chimsedibui/vocabapp';
  static final latestPage = Uri.parse(
    'https://github.com/$repository/releases/latest',
  );

  static List<int>? _version(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(value);
    return match == null
        ? null
        : [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  static bool newer(String candidate, String current) {
    final a = _version(candidate), b = _version(current);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// Reads the CI-published `release.json` of the latest release. The
  /// github.com download redirect has no API rate limit, unlike
  /// api.github.com (60 requests/hour per IP without a token).
  Future<AppRelease?> latest(String current) async {
    try {
      final response = await _client
          .get(
            Uri.parse(
              'https://github.com/$repository/releases/latest/download/release.json',
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404) return null;
      RateLimited.check(response);
      if (response.statusCode != 200) throw const FormatException();
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final version = data['version'] as String;
      if (_version(version) == null) throw const FormatException();
      if (!newer(version, current)) return null;
      final page = 'https://github.com/$repository/releases/tag/v$version';
      final download =
          'https://github.com/$repository/releases/download/v$version';
      final assets = <String, Uri>{};
      for (final asset in (data['assets'] as Map).values) {
        final name = asset['name'] as String, url = asset['url'] as String;
        if (url == '$download/$name' &&
            RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(name)) {
          assets[name] = Uri.parse(url);
          assets['$name.sha256'] = Uri.parse('$url.sha256');
        }
      }
      return AppRelease(version, Uri.parse(page), assets);
    } on RateLimited {
      rethrow;
    } catch (_) {
      throw const UserFacingException(
        'Chưa kiểm tra được bản mới. Hãy thử lại khi có mạng hoặc mở trang phát hành.',
      );
    }
  }

  void close() => _client.close();
}
