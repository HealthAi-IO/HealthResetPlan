import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/network/ai_api.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:health_reset_plan/core/data/health_models.dart';

void main() {
  test('AI 周报响应经过统一解包后仍能读取结构化内容', () async {
    final client = ApiClient(
      adapter: _JsonAdapter(
        '{"code":0,"msg":"成功","data":{"provider":"qwen",'
        '"data":{"summary":"记录稳定","actions":[1,2,3]}}}',
      ),
    );

    final result = await AiApi(client: client).generateWeeklyHealthReport({
      'recordedDays': 3,
    });

    expect(result.provider, 'qwen');
    expect(result.data['summary'], '记录稳定');
    expect(result.data['actions'], [1, 2, 3]);
  });

  test('专属计划请求包含预设目标、自由补充和目标日期', () async {
    final adapter = _JsonAdapter(
      '{"code":0,"msg":"成功","data":{"provider":"qwen",'
      '"rawJson":"{\\"days\\":[]}"}}',
    );
    final client = ApiClient(adapter: adapter);
    final profile = UserProfileData.empty().copyWith(
      gender: 'male',
      birthYear: 1990,
      heightCm: 175,
      weightKg: 70,
    );

    await AiApi(client: client).generatePlan(
      profile: profile,
      recentIndicators: const [],
      provider: 'doubao',
      goal: 'improve_fitness',
      goalDetail: '希望爬三层楼不明显气喘',
      targetDate: DateTime(2026, 10, 1),
    );

    final body = adapter.lastOptions!.data as Map<String, dynamic>;
    expect(body['goal'], 'improve_fitness');
    expect(body['provider'], 'qwen');
    expect(body['goalDetail'], '希望爬三层楼不明显气喘');
    expect(body['targetDate'], '2026-10-01');
    expect(adapter.lastOptions!.receiveTimeout, const Duration(minutes: 6));
  });
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);

  final String body;
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
