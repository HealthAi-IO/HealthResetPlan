import 'package:flutter/services.dart';

class SystemHealthSnapshot {
  const SystemHealthSnapshot({
    required this.steps,
    required this.heartRateBpm,
    required this.sleepHours,
    required this.recordedAt,
    required this.accessStatus,
  });

  final int? steps;
  final int? heartRateBpm;
  final double? sleepHours;
  final DateTime recordedAt;
  final HealthAccessStatus accessStatus;

  factory SystemHealthSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return SystemHealthSnapshot(
      steps: (map['steps'] as num?)?.toInt(),
      heartRateBpm: (map['heartRateBpm'] as num?)?.toInt(),
      sleepHours: (map['sleepHours'] as num?)?.toDouble(),
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['recordedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      accessStatus: HealthAccessStatus.fromMap(
        _mapFrom(map['permissions']),
      ),
    );
  }
}

class HealthAccessStatus {
  const HealthAccessStatus({
    required this.available,
    required this.stepsGranted,
    required this.heartRateGranted,
    required this.sleepGranted,
  });

  final bool available;
  final bool stepsGranted;
  final bool heartRateGranted;
  final bool sleepGranted;

  bool get anyGranted => stepsGranted || heartRateGranted || sleepGranted;
  bool get allGranted => stepsGranted && heartRateGranted && sleepGranted;

  factory HealthAccessStatus.fromMap(Map<dynamic, dynamic> map) {
    return HealthAccessStatus(
      available: map['available'] == true,
      stepsGranted: map['stepsGranted'] == true,
      heartRateGranted: map['heartRateGranted'] == true,
      sleepGranted: map['sleepGranted'] == true,
    );
  }
}

class HealthSyncBridge {
  HealthSyncBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('health_sync_bridge');

  final MethodChannel _channel;

  Future<bool> isAvailable() async {
    final result = await _channel.invokeMethod<bool>('isAvailable');
    return result ?? false;
  }

  Future<HealthAccessStatus> accessStatus() async {
    final raw =
        await _channel.invokeMapMethod<dynamic, dynamic>('accessStatus');
    return HealthAccessStatus.fromMap(raw ?? const {});
  }

  Future<HealthAccessStatus> requestAccess() async {
    final raw =
        await _channel.invokeMapMethod<dynamic, dynamic>('requestAccess');
    return HealthAccessStatus.fromMap(raw ?? const {});
  }

  Future<SystemHealthSnapshot> sync() async {
    final raw = await _channel.invokeMapMethod<dynamic, dynamic>('sync');
    final map = raw ?? <dynamic, dynamic>{};
    return SystemHealthSnapshot.fromMap(map);
  }
}

Map<dynamic, dynamic> _mapFrom(Object? value) {
  if (value is Map) return value;
  return const {};
}
