import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../data/health_models.dart';
import 'api_client.dart';

class AiApi {
  AiApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<AiPlanResult> generatePlan({
    required UserProfileData profile,
    required List<HealthIndicatorEntry> recentIndicators,
    String? provider,
    String goal = 'general',
  }) async {
    final apiProvider = _normalizeProvider(provider);
    final body = _buildPlanRequest(
      profile: profile,
      indicators: recentIndicators,
      goal: goal,
      provider: apiProvider,
    );

    final resp = await _client.dio.post(
      '/ai/plan/generate',
      data: body,
      options: Options(
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    final data = _unwrapData(resp.data);

    return AiPlanResult(
      provider: _displayProvider(data['provider'] as String?, apiProvider),
      rawJson: data['rawJson'] as String? ?? '{}',
    );
  }

  Future<AiChatReply> sendChatMessage({
    required List<Map<String, String>> messages,
    String? provider,
    String? profileSummary,
  }) async {
    final apiProvider = _normalizeProvider(provider);
    final resp = await _client.dio.post('/ai/chat', data: {
      if (apiProvider != null) 'provider': apiProvider,
      'messages': messages,
      if (profileSummary != null) 'profileSummary': profileSummary,
    });
    final data = _unwrapData(resp.data);

    return AiChatReply(
      provider: data['provider'] as String? ?? apiProvider ?? 'oneapi',
      content: data['content'] as String? ?? '',
    );
  }

  Future<void> streamChat({
    required List<Map<String, String>> messages,
    String? provider,
    String? profileSummary,
    required void Function(String token) onToken,
    required void Function() onDone,
    required void Function(String error) onError,
  }) async {
    var completed = false;
    final apiProvider = _normalizeProvider(provider);

    void completeOnce() {
      if (completed) return;
      completed = true;
      onDone();
    }

    try {
      final response = await _client.dio.post(
        '/ai/chat/stream',
        data: {
          if (apiProvider != null) 'provider': apiProvider,
          'messages': messages,
          if (profileSummary != null) 'profileSummary': profileSummary,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          receiveTimeout: const Duration(minutes: 3),
        ),
      );

      final stream = (response.data as ResponseBody).stream;
      var buffer = '';

      await for (final bytes in stream) {
        buffer += utf8.decode(bytes, allowMalformed: true);
        buffer = buffer.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

        while (buffer.contains('\n\n')) {
          final splitIndex = buffer.indexOf('\n\n');
          final eventBlock = buffer.substring(0, splitIndex);
          buffer = buffer.substring(splitIndex + 2);
          final shouldStop = _handleSseEvent(
            eventBlock,
            onToken,
            completeOnce,
            onError,
          );
          if (shouldStop) return;
        }
      }

      if (buffer.trim().isNotEmpty) {
        _handleSseEvent(buffer, onToken, completeOnce, onError);
      }
      completeOnce();
    } on DioException catch (e) {
      await _fallbackToNormalChat(
        messages: messages,
        provider: apiProvider,
        profileSummary: profileSummary,
        onToken: onToken,
        onDone: completeOnce,
        onError: onError,
        fallbackReason: _friendlyDioError(e),
      );
    } catch (e) {
      await _fallbackToNormalChat(
        messages: messages,
        provider: apiProvider,
        profileSummary: profileSummary,
        onToken: onToken,
        onDone: completeOnce,
        onError: onError,
        fallbackReason: '网络异常：$e',
      );
    }
  }

  Future<void> _fallbackToNormalChat({
    required List<Map<String, String>> messages,
    required String? provider,
    required String? profileSummary,
    required void Function(String token) onToken,
    required void Function() onDone,
    required void Function(String error) onError,
    required String fallbackReason,
  }) async {
    try {
      final reply = await sendChatMessage(
        messages: messages,
        provider: provider,
        profileSummary: profileSummary,
      );
      if (reply.content.isNotEmpty) {
        onToken(reply.content);
      }
      onDone();
    } on DioException catch (e) {
      onError(_friendlyDioError(e));
    } catch (_) {
      onError(fallbackReason);
    }
  }

  bool _handleSseEvent(
    String eventBlock,
    void Function(String) onToken,
    void Function() onDone,
    void Function(String) onError,
  ) {
    String? eventName;
    final dataLines = <String>[];

    for (final rawLine in eventBlock.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty || line.startsWith(':')) continue;
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    if (dataLines.isEmpty) return false;

    final data = dataLines.join('\n').trim();
    if (data == '[DONE]') {
      onDone();
      return true;
    }

    if (eventName == 'done') {
      onDone();
      return true;
    }

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      if (eventName == 'error' || json.containsKey('code')) {
        final code = (json['code'] as num?)?.toInt() ?? 0;
        final msg = json['message'] as String? ?? 'AI 服务异常';
        onError(_friendlyCode(code, msg));
        return true;
      }

      final token = json['token'] as String? ?? '';
      if (token.isNotEmpty) onToken(token);
    } catch (_) {
      // Ignore non-JSON SSE comments or malformed keep-alive payloads.
    }
    return false;
  }

  String _friendlyCode(int code, String msg) {
    if (code == 42901) return '今日 AI 使用次数已达上限，明日 0 点重置';
    if (code == 40101) return '当前 AI 模型暂不可用，请稍后重试或切换模型';
    if (code == 40301) return '此功能需要开通会员';
    return msg;
  }

  String? _normalizeProvider(String? provider) {
    final value = provider?.trim();
    if (value == null || value.isEmpty || value == 'auto') return null;
    return value;
  }

  String _displayProvider(String? responseProvider, String? requestedProvider) {
    final value = responseProvider?.trim();
    if (value == null || value.isEmpty || value == 'oneapi') {
      return requestedProvider ?? value ?? 'oneapi';
    }
    return value;
  }

  String _friendlyDioError(DioException e) {
    final body = e.response?.data;
    if (body is Map) {
      final code = (body['code'] as num?)?.toInt() ?? 0;
      final message = (body['message'] ?? body['msg'])?.toString();
      if (code != 0 || message != null) {
        return _friendlyCode(code, message ?? 'AI 服务异常');
      }
    }
    final status = e.response?.statusCode;
    if (status == 429) return '请求过于频繁，请稍后重试';
    if (status == 401) return 'AI 服务未授权，请检查配置';
    if (e.type == DioExceptionType.receiveTimeout) return 'AI 响应超时，请重试';
    return '网络错误：${e.message ?? e.type.name}';
  }

  Map<String, dynamic> _unwrapData(dynamic body) {
    if (body is! Map) return <String, dynamic>{};
    final code = (body['code'] as num?)?.toInt() ?? 0;
    if (code != 0) {
      final options = RequestOptions(path: '');
      throw DioException(
        requestOptions: options,
        response: Response(requestOptions: options, data: body),
        message: (body['message'] ?? body['msg'])?.toString() ?? 'AI 服务异常',
      );
    }
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Map<String, dynamic> _buildPlanRequest({
    required UserProfileData profile,
    required List<HealthIndicatorEntry> indicators,
    required String goal,
    required String? provider,
  }) {
    final age =
        profile.birthYear > 0 ? DateTime.now().year - profile.birthYear : 0;

    String? recentBp;
    double? recentGlucose;
    double? recentTc;
    double? recentLdl;

    for (final ind in indicators) {
      switch (ind.type) {
        case 'bp':
          if (recentBp == null) {
            final s = ind.payload['systolic'];
            final d = ind.payload['diastolic'];
            if (s != null && d != null) recentBp = '$s/$d';
          }
        case 'glucose':
          recentGlucose ??= (ind.payload['glucoseMmol'] as num?)?.toDouble();
        case 'lipid':
          recentTc ??= (ind.payload['tc'] as num?)?.toDouble();
          recentLdl ??= (ind.payload['ldl'] as num?)?.toDouble();
      }
    }

    final bmi = profile.heightCm > 0 && profile.weightKg > 0
        ? profile.weightKg /
            ((profile.heightCm / 100) * (profile.heightCm / 100))
        : 0.0;

    return {
      if (provider != null) 'provider': provider,
      'age': age,
      'gender': profile.gender.isNotEmpty ? profile.gender : 'unknown',
      'heightCm': profile.heightCm,
      'weightKg': profile.weightKg,
      'bmi': double.parse(bmi.toStringAsFixed(1)),
      if (profile.medicalHistory.isNotEmpty)
        'medicalHistory': profile.medicalHistory,
      if (recentBp != null) 'recentBp': recentBp,
      if (recentGlucose != null) 'recentGlucose': recentGlucose,
      if (recentTc != null) 'recentTc': recentTc,
      if (recentLdl != null) 'recentLdl': recentLdl,
      'goal': goal,
      'dietPref':
          profile.dietPreference.isNotEmpty ? profile.dietPreference : 'normal',
      'exerciseBase':
          profile.exerciseBase.isNotEmpty ? profile.exerciseBase : 'none',
    };
  }
}

class AiPlanResult {
  const AiPlanResult({required this.provider, required this.rawJson});

  final String provider;
  final String rawJson;
}

class AiChatReply {
  const AiChatReply({required this.provider, required this.content});

  final String provider;
  final String content;
}
