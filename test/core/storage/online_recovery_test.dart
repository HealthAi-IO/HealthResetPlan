import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:health_reset_plan/core/network/online_data_api.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';
import 'package:health_reset_plan/core/storage/data_sync_status.dart';

class RecoveringApi extends OnlineDataApi {
  RecoveringApi() : super(client: ApiClient());
  bool available = false;
  int saves = 0;

  @override
  Future<OnlineDataSnapshot> load() async {
    if (!available) throw StateError('offline');
    return const OnlineDataSnapshot(version: 7, tables: {
      'meal_settings': [{'id': 1, 'value': 'remote'}],
    });
  }

  @override
  Future<OnlineDataSnapshot> save(
      int version, Map<String, List<Map<String, Object?>>> tables) async {
    saves++;
    return OnlineDataSnapshot(version: version + 1, tables: tables);
  }
}

void main() {
  test('retry after initial connection failure loads remote data without saving', () async {
    final database = AppDatabase.instance;
    final api = RecoveringApi();
    await database.switchSpace('recovery-test');
    addTearDown(database.unbindOnline);
    await expectLater(database.bindOnline(api), throwsStateError);
    expect(dataSyncStatusController.phase, DataSyncPhase.failed);
    api.available = true;
    await dataSyncStatusController.retry();
    expect(dataSyncStatusController.phase, DataSyncPhase.synced);
    expect((await database.query('meal_settings')).single['value'], 'remote');
    expect(api.saves, 0);
  });
}
