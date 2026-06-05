import '../storage/app_database.dart';
import 'device_models.dart';

/// 已绑定设备的本地仓库
class DeviceRepository {
  DeviceRepository({required AppDatabase database}) : _database = database;
  final AppDatabase _database;

  /// 加载所有已绑定设备
  Future<List<BoundDevice>> listBound() async {
    final db = await _database.open();
    final rows = await db.query(
      'bound_device',
      orderBy: 'bound_at DESC',
    );
    return rows.map(BoundDevice.fromRow).toList();
  }

  /// 通过 MAC 查询某设备是否已绑定
  Future<BoundDevice?> findByMac(String mac) async {
    final db = await _database.open();
    final rows = await db.query(
      'bound_device',
      where: 'mac_address = ?',
      whereArgs: [mac],
      limit: 1,
    );
    return rows.isEmpty ? null : BoundDevice.fromRow(rows.first);
  }

  /// 绑定设备
  Future<int> bind({
    required DeviceKind kind,
    required String name,
    required String macAddress,
    DeviceSyncSource syncSource = DeviceSyncSource.bleLive,
    String brand = '',
  }) async {
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert(
      'bound_device',
      {
        'kind': kind.code,
        'brand': brand,
        'name': name,
        'mac_address': macAddress,
        'sync_source': syncSource.code,
        'status': 'active',
        'bound_at': now,
        'last_sync_at': 0,
        'sync_state': 'idle',
        'last_error': '',
      },
      replace: true,
    );
  }

  /// 解绑设备
  Future<void> unbind(int id) async {
    final db = await _database.open();
    await db.delete('bound_device', where: 'id = ?', whereArgs: [id]);
  }

  /// 更新最近同步时间
  Future<void> updateLastSync(int id) async {
    final db = await _database.open();
    await db.update(
      'bound_device',
      {
        'last_sync_at': DateTime.now().millisecondsSinceEpoch,
        'sync_state': 'idle',
        'last_error': '',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateSyncState(
    int id, {
    required String syncState,
    String lastError = '',
  }) async {
    final db = await _database.open();
    await db.update(
      'bound_device',
      {
        'sync_state': syncState,
        'last_error': lastError,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
