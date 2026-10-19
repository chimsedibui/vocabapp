import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';

class AppRelease {
  const AppRelease(this.version, this.page, this.assets);
  final String version;
  final Uri page;
  final Map<String, Uri> assets;
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

  Future<AppRelease?> latest(String current) async {
    try {
      final response = await _client
          .get(
            Uri.parse(
              'https://api.github.com/repos/$repository/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) throw const FormatException();
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = data['tag_name'] as String;
      if (!newer(tag, current)) return null;
      if (data['draft'] != false || data['prerelease'] != false) {
        throw const FormatException();
      }
      final expectedPage = 'https://github.com/$repository/releases/tag/$tag';
      if (data['html_url'] != expectedPage) throw const FormatException();
      final assets = <String, Uri>{};
      for (final asset in data['assets'] as List) {
        final name = asset['name'] as String,
            url = asset['browser_download_url'] as String;
        if (url ==
                'https://github.com/$repository/releases/download/$tag/$name' &&
            RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(name)) {
          assets[name] = Uri.parse(url);
        }
      }
      return AppRelease(
        tag.replaceFirst(RegExp('^v'), ''),
        Uri.parse(expectedPage),
        assets,
      );
    } catch (_) {
      throw const UserFacingException(
        'Chưa kiểm tra được bản mới. Hãy thử lại khi có mạng hoặc mở trang phát hành.',
      );
    }
  }

  void close() => _client.close();
}
