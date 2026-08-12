import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';
import 'package:health_reset_plan/core/data/health_repository.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:health_reset_plan/core/network/auth_api.dart';
import 'package:health_reset_plan/core/network/online_data_api.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';
import 'package:health_reset_plan/core/storage/data_sync_merge.dart';

void main() {
  final cloud = _JourneyAdapter();
  final client = ApiClient(adapter: cloud);
  final database = AppDatabase.instance;
  final repository = HealthRepository(database: database);

  setUpAll(() async {
    await database.open();
    await database.switchSpace('e2e-main-journeys');
    await database.bindOnline(OnlineDataApi(client: client));
    await repository.initialize();
  });

  test('主链路 1：密码登录并取得账号会话', () async {
    final result = await AuthApi(client: client).loginWithPhonePassword(
      phone: '13800000000',
      password: 'test-password',
      captchaTicket: 'verified-ticket',
    );
    expect(result.userId, 'e2e-user');
    expect(result.accessToken, isNotEmpty);
  });

  test('主链路 2：录入指标后可从历史记录读取', () async {
    await repository.addIndicator(
      type: 'weight',
      payload: const {'weightKg': 68.5},
      source: 'e2e',
    );
    final entries = await repository.loadIndicators(type: 'weight');
    expect(entries.first.payload['weightKg'], 68.5);
  });

  test('主链路 3：记录餐食并自动形成饮食打卡', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await repository.saveMealRecord(MealRecordData(
      clientId: HealthRepository.newClientId(),
      name: 'E2E 测试餐',
      mealType: 'lunch',
      eatenAt: now,
      imagePath: '',
      totalCalories: 520,
      proteinG: 25,
      carbsG: 60,
      fatG: 18,
      healthScore: 80,
      glycemicLoad: 12,
      foods: const [],
      nutrition: const {},
      createdAt: now,
      updatedAt: now,
    ));
    final meals = await repository.loadMealsForDate(DateTime.now());
    final clocks = await repository.loadClockRecords();
    expect(meals.any((meal) => meal.name == 'E2E 测试餐'), isTrue);
    expect(clocks.any((clock) => clock.type == 'meal'), isTrue);
  });

  test('主链路 4：应用计划后完成运动打卡', () async {
    await repository.applyAiPlan(
      provider: 'e2e',
      createReminders: false,
      plan: const {
        'days': [
          {
            'exercise': {'name': '快走', 'durationMinutes': 20},
            'measurements': ['记录体重'],
          }
        ],
      },
    );
    await repository.addClockRecord(type: 'exercise', note: 'E2E 快走完成');
    expect(await repository.loadPlans(), isNotEmpty);
    expect(
      (await repository.loadClockRecords())
          .any((record) => record.note == 'E2E 快走完成'),
      isTrue,
    );
  });

  test('主链路 5：跨端冲突保留用户选择且合并独立记录', () {
    final result = mergeDataSyncTables(
      base: const {
        'health_indicator': [
          {'client_id': 'same', 'value': 70}
        ]
      },
      local: const {
        'health_indicator': [
          {'client_id': 'same', 'value': 69},
          {'client_id': 'local-only', 'value': 120}
        ]
      },
      remote: const {
        'health_indicator': [
          {'client_id': 'same', 'value': 71},
          {'client_id': 'remote-only', 'value': 5.6}
        ]
      },
    );
    final key = result.conflicts.single.rowKey;
    final resolved = result.resolve({key: DataSyncConflictChoice.local});
    expect(resolved['health_indicator'], hasLength(3));
    expect(
      resolved['health_indicator']!
          .firstWhere((row) => row['client_id'] == 'same')['value'],
      69,
    );
  });
}

class _JourneyAdapter implements HttpClientAdapter {
  int version = 0;
  Map<String, dynamic> tables = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object data;
    if (options.path.endsWith('/auth/login')) {
      data = {
        'userId': 'e2e-user',
        'accessToken': 'e2e-access-token',
        'refreshToken': 'e2e-refresh-token',
        'accessExpiresIn': 900,
        'hasPassword': true,
      };
    } else if (options.method == 'GET' && options.path.endsWith('/data')) {
      data = {'version': version, 'data': tables};
    } else if (options.method == 'PUT' && options.path.endsWith('/data')) {
      final body = Map<String, dynamic>.from(options.data as Map);
      version++;
      tables = Map<String, dynamic>.from(body['data'] as Map);
      data = {'version': version, 'data': tables};
    } else {
      data = <String, dynamic>{};
    }
    return ResponseBody.fromString(
      jsonEncode({'code': 0, 'msg': '成功', 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
