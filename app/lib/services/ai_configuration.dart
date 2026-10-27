import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/models.dart';

enum AiProvider { openai, azure, gemini }

class AiConfiguration {
  const AiConfiguration({
    required this.provider,
    required this.key,
    required this.model,
    this.endpoint = '',
    this.structured = true,
    this.contextWindow = 16384,
  });
  final AiProvider provider;
  final String key, model, endpoint;
  final bool structured;
  final int contextWindow;
  String get label => switch (provider) {
    AiProvider.openai => 'OpenAI',
    AiProvider.azure => 'Azure OpenAI',
    AiProvider.gemini => 'Google Gemini',
  };
  Uri get uri {
    if (provider == AiProvider.openai) {
      return Uri.https('api.openai.com', '/v1/chat/completions');
    }
    if (provider == AiProvider.gemini) {
      return Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/openai/chat/completions',
      );
    }
    final root = Uri.tryParse(endpoint);
    if (root == null ||
        root.scheme != 'https' ||
        root.userInfo.isNotEmpty ||
        !root.host.endsWith('.openai.azure.com') ||
        root.hasQuery ||
        root.hasFragment ||
        root.hasPort ||
        !['', '/', '/openai/v1', '/openai/v1/'].contains(root.path)) {
      throw const UserFacingException(
        'Azure cần endpoint HTTPS dạng https://TEN.openai.azure.com (API v1).',
      );
    }
    return root.replace(path: '/openai/v1/chat/completions');
  }

  void validate() {
    uri;
    if (key.trim().isEmpty ||
        key.length > 4096 ||
        key.contains(RegExp(r'[\r\n]')) ||
        model.trim().isEmpty ||
        model.length > 200 ||
        contextWindow < 6500 ||
        contextWindow > 2000000) {
      throw const UserFacingException(
        'Kiểm tra API key, tên model/deployment và context window (6.500–2.000.000).',
      );
    }
  }

  // No key included in cache keys, jobs, backups, logs, or error messages.
  String get identity => jsonEncode([
    provider.name,
    uri.toString(),
    model,
    structured,
    contextWindow,
  ]);
  Map<String, Object> toJson() => {
    'provider': provider.name,
    'key': key,
    'model': model,
    'endpoint': endpoint,
    'structured': structured,
    'context': contextWindow,
  };
  factory AiConfiguration.fromJson(Map<String, dynamic> json) =>
      AiConfiguration(
        provider: AiProvider.values.byName(json['provider'] as String),
        key: json['key'] as String,
        model: json['model'] as String,
        endpoint: json['endpoint'] as String,
        structured: json['structured'] as bool,
        contextWindow: json['context'] as int,
      );
}

class AiPreferences {
  const AiPreferences(this.primary, [this.fallback]);
  final AiConfiguration primary;
  final AiConfiguration? fallback;
  String get identity => '${primary.identity}|${fallback?.identity ?? ''}';
}

class AiConfigurationStore {
  const AiConfigurationStore({this.storage = const FlutterSecureStorage()});
  final FlutterSecureStorage storage;
  static const _key = 'vocabapp.ai.v1';
  Future<AiPreferences?> load() async {
    try {
      final value = await storage.read(key: _key);
      if (value == null) return null;
      final root = jsonDecode(value) as Map<String, dynamic>;
      return AiPreferences(
        AiConfiguration.fromJson(root['primary'] as Map<String, dynamic>),
        root['fallback'] == null
            ? null
            : AiConfiguration.fromJson(
                root['fallback'] as Map<String, dynamic>,
              ),
      );
    } catch (_) {
      throw const UserFacingException(
        'Không đọc được cấu hình API trong kho bảo mật. Hãy cấu hình lại trong Cài đặt.',
      );
    }
  }

  Future<void> save(AiPreferences value) async {
    value.primary.validate();
    value.fallback?.validate();
    try {
      await storage.write(
        key: _key,
        value: jsonEncode({
          'primary': value.primary.toJson(),
          'fallback': value.fallback?.toJson(),
        }),
      );
    } catch (_) {
      throw const UserFacingException(
        'Không lưu được API vào kho bảo mật của thiết bị.',
      );
    }
  }

  Future<void> clear() async {
    try {
      await storage.delete(key: _key);
    } catch (_) {
      throw const UserFacingException(
        'Không xóa được cấu hình API. Hãy thử lại.',
      );
    }
  }
}
