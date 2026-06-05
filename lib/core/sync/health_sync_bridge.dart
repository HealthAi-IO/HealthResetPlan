import 'package:flutter/services.dart';

class SystemHealthSnapshot {
  const SystemHealthSnapshot({
    required this.steps,
    required this.heartRateBpm,
    required this.sleepHours,
    required this.recordedAt,
  });

  final int? steps;
  final int? heartRateBpm;
  final double? sleepHours;
  final DateTime recordedAt;

  factory SystemHealthSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return SystemHealthSnapshot(
      steps: (map['steps'] as num?)?.toInt(),
      heartRateBpm: (map['heartRateBpm'] as num?)?.toInt(),
      sleepHours: (map['sleepHours'] as num?)?.toDouble(),
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['recordedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
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

  Future<bool> requestAccess() async {
    final result = await _channel.invokeMethod<bool>('requestAccess');
    return result ?? false;
  }

  Future<SystemHealthSnapshot> sync() async {
    final raw = await _channel.invokeMapMethod<dynamic, dynamic>('sync');
    final map = raw ?? <dynamic, dynamic>{};
    return SystemHealthSnapshot.fromMap(map);
  }
}

