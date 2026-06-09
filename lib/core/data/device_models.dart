/// 蓝牙设备类型
enum DeviceKind {
  bloodPressure('blood_pressure', '血压计', '🩺'),
  weightScale('weight_scale', '体脂秤', '⚖️'),
  heartRate('heart_rate', '心率手环', '❤️'),
  band('band', '智能手环', '⌚'),
  unknown('unknown', '其他设备', '📡');

  const DeviceKind(this.code, this.label, this.emoji);
  final String code;
  final String label;
  final String emoji;

  static DeviceKind fromCode(String code) => DeviceKind.values.firstWhere(
        (e) => e.code == code,
        orElse: () => DeviceKind.unknown,
      );
}

enum DeviceSyncSource {
  bleLive('ble_live', 'BLE 实时采集'),
  systemHealth('system_health', '系统健康同步'),
  manual('manual', '手动录入');

  const DeviceSyncSource(this.code, this.label);
  final String code;
  final String label;

  static DeviceSyncSource fromCode(String code) =>
      DeviceSyncSource.values.firstWhere(
        (e) => e.code == code,
        orElse: () => DeviceSyncSource.bleLive,
      );
}

/// 已绑定设备记录
class BoundDevice {
  BoundDevice({
    required this.id,
    required this.kind,
    required this.brand,
    required this.name,
    required this.macAddress,
    required this.syncSource,
    required this.status,
    required this.boundAt,
    required this.lastSyncAt,
    required this.syncState,
    required this.lastError,
  });

  final int id;
  final DeviceKind kind;
  final String brand;
  final String name;
  final String macAddress;
  final DeviceSyncSource syncSource;
  final String status; // active / disabled
  final int boundAt;
  final int lastSyncAt;
  final String syncState;
  final String lastError;

  factory BoundDevice.fromRow(Map<String, Object?> row) => BoundDevice(
        id: row['id'] as int,
        kind: DeviceKind.fromCode((row['kind'] as String?) ?? 'unknown'),
        brand: (row['brand'] as String?) ?? '',
        name: (row['name'] as String?) ?? '',
        macAddress: (row['mac_address'] as String?) ?? '',
        syncSource: DeviceSyncSource.fromCode(
          (row['sync_source'] as String?) ?? 'ble_live',
        ),
        status: (row['status'] as String?) ?? 'active',
        boundAt: (row['bound_at'] as int?) ?? 0,
        lastSyncAt: (row['last_sync_at'] as int?) ?? 0,
        syncState: (row['sync_state'] as String?) ?? 'idle',
        lastError: (row['last_error'] as String?) ?? '',
      );

  Map<String, Object?> toRow() => {
        if (id > 0) 'id': id,
        'kind': kind.code,
        'brand': brand,
        'name': name,
        'mac_address': macAddress,
        'sync_source': syncSource.code,
        'status': status,
        'bound_at': boundAt,
        'last_sync_at': lastSyncAt,
        'sync_state': syncState,
        'last_error': lastError,
      };
}

/// 扫描到的设备（未绑定）
class ScannedDevice {
  ScannedDevice({
    required this.id, // 平台 ID（Android 是 MAC，iOS 是 UUID）
    required this.name,
    required this.rssi,
    required this.serviceUuids,
    this.connectable = true,
    this.manufacturerIds = const [],
  });

  final String id;
  final String name;
  final int rssi;
  final List<String> serviceUuids;
  final bool connectable;
  final List<int> manufacturerIds;

  /// 根据广播的 GATT 服务 UUID 推断设备类型
  DeviceKind get inferredKind {
    final uuids = serviceUuids.map((e) => e.toLowerCase()).toList();
    if (uuids.any((u) => u.contains('1810'))) return DeviceKind.bloodPressure;
    if (uuids.any((u) => u.contains('181d') || u.contains('181b'))) {
      return DeviceKind.weightScale;
    }
    if (uuids.any((u) => u.contains('180d'))) return DeviceKind.heartRate;
    // 名字辅助判断
    final n = name.toLowerCase();
    if (n.contains('bp') || n.contains('blood') || n.contains('血压')) {
      return DeviceKind.bloodPressure;
    }
    if (n.contains('scale') ||
        n.contains('weight') ||
        n.contains('体重') ||
        n.contains('体脂')) {
      return DeviceKind.weightScale;
    }
    if (n.contains('band') ||
        n.contains('mi band') ||
        n.contains('huawei') ||
        n.contains('honor') ||
        n.contains('手环') ||
        n.contains('watch') ||
        n.contains('gt ') ||
        n.contains('fit ')) {
      return DeviceKind.band;
    }
    return DeviceKind.unknown;
  }

  bool get hasStandardBleMeasurement {
    final uuids = serviceUuids.map((e) => e.toLowerCase()).toList();
    return uuids.any((u) =>
        u.contains('1810') ||
        u.contains('181d') ||
        u.contains('181b') ||
        u.contains('180d'));
  }

  bool get isWearableBand => inferredKind == DeviceKind.band;
}
