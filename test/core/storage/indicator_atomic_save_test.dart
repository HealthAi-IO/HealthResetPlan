import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_repository.dart';
import 'package:health_reset_plan/core/data/health_models.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:health_reset_plan/core/network/online_data_api.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';

class RecordingApi extends OnlineDataApi {
  RecordingApi() : super(client: ApiClient());
  int saves = 0;
  bool fail = false;
  @override
  Future<OnlineDataSnapshot> load() async =>
      OnlineDataSnapshot(version: 0, tables: {
        'user_profile': [
          UserProfileData.empty().copyWith(heightCm: 170, weightKg: 60).toRow()
            ..['id'] = 1
        ],
      });
  @override
  Future<OnlineDataSnapshot> save(
      int version, Map<String, List<Map<String, Object?>>> tables) async {
    saves++;
    if (fail) throw StateError('offline');
    return OnlineDataSnapshot(version: version + 1, tables: tables);
  }
}

void main() {
  test('编辑指标同时保存测量时间和数值', () async {
    final db = AppDatabase.instance;
    final api = RecordingApi();
    await db.switchSpace('indicator-edit-time-test');
    await db.bindOnline(api);
    addTearDown(db.unbindOnline);
    final repo = HealthRepository(database: db);
    final originalTime = DateTime(2026, 10, 30, 8);
    final revisedTime = DateTime(2026, 10, 31, 9);
    final id = await repo.addIndicator(
      type: 'glucose', payload: {'glucoseMmol': 5.6}, measuredAt: originalTime,
    );
    await repo.updateIndicator(id, {'glucoseMmol': 5.7}, measuredAt: revisedTime);
    final entries = await repo.loadIndicators(type: 'glucose');
    expect(entries.single.payload['glucoseMmol'], 5.7);
    expect(entries.single.measuredAt, revisedTime.millisecondsSinceEpoch);
    expect(api.saves, 2);
  });

  for (final fail in [false, true]) {
    test('weight and associated records commit once, failure=$fail', () async {
      final db = AppDatabase.instance;
      final api = RecordingApi()..fail = fail;
      await db.switchSpace('weight-test');
      await db.bindOnline(api);
      addTearDown(db.unbindOnline);
      final repo = HealthRepository(database: db);
      final operation = repo.addIndicator(
          type: 'weight', payload: {'weightKg': 59}, clockNote: '体重59kg');
      if (fail) {
        await expectLater(operation, throwsStateError);
      } else {
        await operation;
      }
      expect(api.saves, 1);
      expect(await db.count('health_indicator'), fail ? 0 : 2);
      expect(await db.count('clock_record'), fail ? 0 : 1);
      expect((await repo.loadProfile())!.weightKg, fail ? 60 : 59);
    });
  }
}
