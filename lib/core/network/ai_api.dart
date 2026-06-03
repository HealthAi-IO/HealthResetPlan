import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../data/health_models.dart';
import 'api_client.dart';

/// AI 计划生成 + 对话 API。
///
/// 所有接口均需要有效 JWT（会员资格在服务端校验）。
/// 对话支持流式（SSE）和非流式两种模式。
class AiApi {
  AiApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  // ── 生成 7 天健康方案（非流式） ────────────────────────────────

  Future<AiPlanResult> generatePlan({
    required UserProfileData profile,
    required List<HealthIndicatorEntry> recentIndicators,
    String goal = 'general',
  }) async {
    final body = _buildPlanRequest(
      profile: profile,
      indicators: recentIndicators,
      goal: goal,
    );

    final resp = await _client.dio.post('/ai/plan/generate', data: body);
    final data = resp.data['data'] as Map<String, dynamic>;

    return AiPlanResult(
      provider: data['provider'] as String? ?? 'oneapi',
      rawJson: data['rawJson'] as String? ?? '{}',
    );
  }

  // ── 非流式对话（保留兼容） ─────────────────────────────────────

  Future<AiChatReply> sendChatMessage({
    required List<Map<String, String>> messages,
    String? profileSummary,
  }) async {
    final resp = await _client.dio.post('/ai/chat', data: {
      'messages': messages,
      if (profileSummary != null) 'profileSummary': profileSummary,
    });
    final data = resp.data['data'] as Map<String, dynamic>;

    return AiChatReply(
      provider: data['provider'] as String? ?? 'oneapi',
      content: data['content'] as String? ?? '',
    );
  }

  // ── 流式对话（SSE） ────────────────────────────────────────────

  /// 向后端 `/ai/chat/stream` 发起 SSE 请求，逐 token 回调。
  ///
  /// - [onToken]  每收到一个 token 调用一次
  /// - [onDone]   流正常结束时调用
  /// - [onError]  发生错误时调用，参数为错误描述
  Future<void> streamChat({
    required List<Map<String, String>> messages,
    String? profileSummary,
    required void Function(String token) onToken,
    required void Function() onDone,
    required void Function(String error) onError,
  }) async {
    try {
      final response = await _client.dio.post(
        '/ai/chat/stream',
        data: {
          'messages': messages,
          if (profileSummary != null) 'profileSummary': profileSummary,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          receiveTimeout: const Duration(seconds: 90),
        ),
      );

      final stream = (response.data as ResponseBody).stream;
      String buffer = '';

      await for (final bytes in stream) {
        buffer += utf8.decode(bytes, allowMalformed: true);

        // SSE 以 \n\n 分隔事件，逐行处理
        final lines = buffer.split('\n');
        buffer = lines.last; // 最后一行可能不完整，留到下次

        String? eventName;
        for (final raw in lines.sublist(0, lines.length - 1)) {
          final line = raw.trim();
          if (line.startsWith('event: ')) {
            eventName = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') {
              onDone();
              return;
            }
            _handleSseLine(data, eventName, onToken, onDone, onError);
            eventName = null;
          }
        }
      }
      // 流结束但没收到 [DONE]
      onDone();
    } on DioException catch (e) {
      onError(_friendlyDioError(e));
    } catch (e) {
      onError('网络异常：$e');
    }
  }

  void _handleSseLine(
    String data,
    String? eventName,
    void Function(String) onToken,
    void Function() onDone,
    void Function(String) onError,
  ) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;

      if (eventName == 'error' || json.containsKey('code')) {
        final code = json['code'] as int? ?? 0;
        final msg = json['message'] as String? ?? 'AI 服务异常';
        onError(_friendlyCode(code, msg));
        return;
      }

      if (eventName == 'done') {
        onDone();
        return;
      }

      final token = json['token'] as String? ?? '';
      if (token.isNotEmpty) onToken(token);
    } catch (_) {
      // 非 JSON 行（如注释行）忽略
    }
  }

  String _friendlyCode(int code, String msg) {
    if (code == 42901) return '今日 AI 使用次数已达上限，明日 0 点重置';
    if (code == 40101) return 'AI 服务密钥失效，请联系管理员';
    if (code == 40301) return '此功能需要开通会员';
    return msg;
  }

  String _friendlyDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 429) return '请求过于频繁，请稍后重试';
    if (status == 401) return 'AI 服务未授权，请检查配置';
    if (e.type == DioExceptionType.receiveTimeout) return 'AI 响应超时，请重试';
    return '网络错误：${e.message ?? e.type.name}';
  }

  // ── 内部：构建计划请求体 ───────────────────────────────────────

  Map<String, dynamic> _buildPlanRequest({
    required UserProfileData profile,
    required List<HealthIndicatorEntry> indicators,
    required String goal,
  }) {
    final age = profile.birthYear > 0 ? DateTime.now().year - profile.birthYear : 0;

    String? recentBp;
    double? recentGlucose, recentTc, recentLdl;

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
        ? profile.weightKg / ((profile.heightCm / 100) * (profile.heightCm / 100))
        : 0.0;

    return {
      'age': age,
      'gender': profile.gender.isNotEmpty ? profile.gender : 'unknown',
      'heightCm': profile.heightCm,
      'weightKg': profile.weightKg,
      'bmi': double.parse(bmi.toStringAsFixed(1)),
      if (profile.medicalHistory.isNotEmpty) 'medicalHistory': profile.medicalHistory,
      if (recentBp != null) 'recentBp': recentBp,
      if (recentGlucose != null) 'recentGlucose': recentGlucose,
      if (recentTc != null) 'recentTc': recentTc,
      if (recentLdl != null) 'recentLdl': recentLdl,
      'goal': goal,
      'dietPref': profile.dietPreference.isNotEmpty ? profile.dietPreference : 'normal',
      'exerciseBase': profile.exerciseBase.isNotEmpty ? profile.exerciseBase : 'none',
    };
  }
}

// ── 结果数据类 ────────────────────────────────────────────────

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
