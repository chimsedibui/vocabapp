import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/passage.dart';
import 'ai_configuration.dart';

class PassageCancelled extends UserFacingException {
  const PassageCancelled() : super('Đã hủy. Passage vẫn được giữ để thử lại.');
}

class _Refusal extends UserFacingException {
  const _Refusal()
    : super(
        'Model từ chối hoặc bộ lọc nội dung chặn yêu cầu. Không gọi dự phòng.',
      );
}

class _Incomplete extends UserFacingException {
  const _Incomplete()
    : super(
        'Output bị cắt hoặc chưa hoàn tất. Hãy giảm số từ hoặc chia đoạn; app không tự gọi lại.',
      );
}

Map<String, Object?>? _usage(Object? raw) {
  if (raw is! Map) return null;
  final result = <String, Object?>{};
  for (final key in ['prompt_tokens', 'completion_tokens', 'total_tokens']) {
    if (raw[key] is int && (raw[key] as int) >= 0) result[key] = raw[key];
  }
  for (final key in ['prompt_tokens_details', 'completion_tokens_details']) {
    if (raw[key] is Map) {
      final details = raw[key] as Map;
      result[key] = {
        for (final name in [
          'cached_tokens',
          'reasoning_tokens',
          'audio_tokens',
          'accepted_prediction_tokens',
          'rejected_prediction_tokens',
        ])
          if (details[name] is int && (details[name] as int) >= 0)
            name: details[name],
      };
    }
  }
  return result.isEmpty ? null : result;
}

class ExtractionResponse {
  const ExtractionResponse(this.result, this.configuration);
  final PassageResult result;
  final AiConfiguration configuration;
}

/// One user action, at most three HTTP requests, no tools or hidden enrichment.
class PassageService {
  PassageService({http.Client Function()? clientFactory})
    : _factory = clientFactory ?? http.Client.new;
  final http.Client Function() _factory;
  http.Client? _active;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _active?.close();
  }

  void _check() {
    if (_cancelled) throw const PassageCancelled();
  }

  Future<ExtractionResponse> extract(
    PassageRequest request,
    AiPreferences preferences, {
    required Future<void> Function(Map<String, Object?>) onAttempt,
  }) async {
    preferences.primary.validate();
    preferences.fallback?.validate();
    request.checkBudget(preferences.primary.contextWindow);
    if (preferences.fallback != null) {
      request.checkBudget(preferences.fallback!.contextWindow);
    }
    final clock = Stopwatch()..start();
    UserFacingException? lastError;
    var requests = 0;
    for (var attempt = 0; attempt < 3; attempt++) {
      _check();
      if (clock.elapsedMilliseconds >= 120000) break;
      final config = attempt == 2 && preferences.fallback != null
          ? preferences.fallback!
          : preferences.primary;
      final record = <String, Object?>{
        'provider': config.provider.name,
        'model': config.model,
        'attempt': ++requests,
        'usage': null,
      };
      final client = _factory();
      _active = client;
      ExtractionResponse? success;
      UserFacingException? failure;
      try {
        final seconds = ((120000 - clock.elapsedMilliseconds) / 1000)
            .floor()
            .clamp(1, 40);
        final response = await _send(
          client,
          request,
          config,
        ).timeout(Duration(seconds: seconds));
        _check();
        record['http_status'] = response.statusCode;
        if (response.statusCode != 200) {
          if (response.statusCode == 400 &&
              response.body.contains('content_filter')) {
            throw const _Refusal();
          }
          throw UserFacingException(switch (response.statusCode) {
            401 || 403 => '${config.label}: key/quyền truy cập không hợp lệ.',
            429 => '${config.label}: hết quota hoặc giới hạn tốc độ.',
            400 || 404 =>
              '${config.label}: kiểm tra model/deployment và chế độ JSON trong Cài đặt.',
            _ =>
              '${config.label}: dịch vụ chưa khả dụng (HTTP ${response.statusCode}).',
          });
        }
        final root = jsonDecode(response.body) as Map<String, dynamic>;
        record['usage'] = _usage(root['usage']);
        final choice = (root['choices'] as List).single as Map<String, dynamic>;
        final message = choice['message'] as Map<String, dynamic>;
        if (message['refusal'] != null ||
            choice['finish_reason'] == 'content_filter') {
          throw const _Refusal();
        }
        if (choice['finish_reason'] != 'stop') throw const _Incomplete();
        final result = validatePassageResult(
          message['content'] as String,
          request,
        );
        record['status'] = 'success';
        success = ExtractionResponse(result, config);
      } catch (e) {
        failure = _cancelled
            ? const PassageCancelled()
            : e is UserFacingException
            ? e
            : const UserFacingException(
                'Kết nối lỗi, quá thời gian hoặc response không hợp lệ.',
              );
        record['status'] = _cancelled
            ? 'cancelled'
            : e is _Refusal
            ? 'refused'
            : 'error';
      } finally {
        client.close();
        if (identical(_active, client)) _active = null;
      }
      // A local accounting/storage error must not trigger another paid request.
      await onAttempt(record);
      _check();
      if (success != null) return success;
      lastError = failure!;
      if (failure is _Refusal || failure is _Incomplete) throw failure;
      if ([400, 401, 403, 404].contains(record['http_status'])) {
        if (preferences.fallback == null || attempt == 2) break;
        attempt = 1;
      } else if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    _check();
    throw lastError ??
        const UserFacingException('Đã hết thời gian cho lần trích này.');
  }

  Future<http.Response> _send(
    http.Client client,
    PassageRequest request,
    AiConfiguration config,
  ) async {
    final message = http.Request('POST', config.uri)
      ..followRedirects = false
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (config.provider == AiProvider.openai)
          'Authorization': 'Bearer ${config.key}'
        else
          'api-key': config.key,
      })
      ..body = jsonEncode({
        'model': config.model,
        'store': false,
        'max_completion_tokens': 2500,
        'messages': [
          {'role': 'system', 'content': request.instruction},
          {'role': 'user', 'content': request.text},
        ],
        'response_format': config.structured
            ? {
                'type': 'json_schema',
                'json_schema': {
                  'name': 'passage_vocabulary',
                  'strict': true,
                  'schema': passageSchema,
                },
              }
            : {'type': 'json_object'},
      });
    final response = await client.send(message);
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      _check();
      if (bytes.length + chunk.length > 256 * 1024) {
        throw const FormatException('Response too large');
      }
      bytes.addAll(chunk);
    }
    return http.Response.bytes(
      bytes,
      response.statusCode,
      headers: response.headers,
    );
  }
}
