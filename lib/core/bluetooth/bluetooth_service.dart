import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

import '../data/device_models.dart';

class MeasurementReading {
  MeasurementReading({
    required this.kind,
    required this.payload,
    required this.measuredAt,
  });

  final DeviceKind kind;
  final Map<String, dynamic> payload;
  final DateTime measuredAt;
}

class HealthBundleReading {
  HealthBundleReading({
    required this.kind,
    required this.payload,
    required this.measuredAt,
    required this.source,
  });

  final DeviceKind kind;
  final Map<String, dynamic> payload;
  final DateTime measuredAt;
  final DeviceSyncSource source;
}

class BluetoothService {
  BluetoothService._();
  static final BluetoothService instance = BluetoothService._();

  static const _svcBloodPressure = '00001810-0000-1000-8000-00805f9b34fb';
  static const _chrBpMeasurement = '00002a35-0000-1000-8000-00805f9b34fb';

  static const _svcWeightScale = '0000181d-0000-1000-8000-00805f9b34fb';
  static const _chrWeightMeasurement = '00002a9d-0000-1000-8000-00805f9b34fb';

  static const _svcHeartRate = '0000180d-0000-1000-8000-00805f9b34fb';
  static const _chrHeartRateMeasurement = '00002a37-0000-1000-8000-00805f9b34fb';

  Future<bool> ensurePermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return results.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<bool> isBluetoothOn() async {
    try {
      return await fbp.FlutterBluePlus.adapterState.first ==
          fbp.BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  Future<void> turnOn() async {
    try {
      await fbp.FlutterBluePlus.turnOn();
    } catch (_) {}
  }

  Stream<List<ScannedDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    if (fbp.FlutterBluePlus.isScanningNow) {
      await fbp.FlutterBluePlus.stopScan();
    }

    await fbp.FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: fbp.AndroidScanMode.balanced,
    );

    final seen = <String, ScannedDevice>{};
    await for (final results in fbp.FlutterBluePlus.scanResults) {
      for (final r in results) {
        final name = r.device.platformName.trim();
        if (name.isEmpty) continue;
        seen[r.device.remoteId.str] = ScannedDevice(
          id: r.device.remoteId.str,
          name: name,
          rssi: r.rssi,
          serviceUuids: r.advertisementData.serviceUuids.map((u) => u.str).toList(),
        );
      }
      yield seen.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    }
  }

  Future<void> stopScan() async {
    if (fbp.FlutterBluePlus.isScanningNow) {
      await fbp.FlutterBluePlus.stopScan();
    }
  }

  Future<Stream<MeasurementReading>> connectAndSubscribe(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    await device.connect(timeout: timeout, autoConnect: false);

    final services = await device.discoverServices();
    final controller = StreamController<MeasurementReading>();

    device.connectionState.listen((state) {
      if (state == fbp.BluetoothConnectionState.disconnected) {
        controller.close();
      }
    });

    for (final svc in services) {
      final svcId = svc.uuid.str128.toLowerCase();
      for (final chr in svc.characteristics) {
        final chrId = chr.uuid.str128.toLowerCase();
        if (svcId == _svcBloodPressure && chrId == _chrBpMeasurement) {
          await _subscribeCharacteristic(chr, (bytes) {
            final reading = _parseBloodPressure(bytes);
            if (reading != null) controller.add(reading);
          });
        } else if (svcId == _svcWeightScale && chrId == _chrWeightMeasurement) {
          await _subscribeCharacteristic(chr, (bytes) {
            final reading = _parseWeight(bytes);
            if (reading != null) controller.add(reading);
          });
        } else if (svcId == _svcHeartRate && chrId == _chrHeartRateMeasurement) {
          await _subscribeCharacteristic(chr, (bytes) {
            final reading = _parseHeartRate(bytes);
            if (reading != null) controller.add(reading);
          });
        }
      }
    }

    return controller.stream;
  }

  Future<void> disconnect(String deviceId) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    if (device.isConnected) {
      await device.disconnect();
    }
  }

  Future<void> _subscribeCharacteristic(
    fbp.BluetoothCharacteristic chr,
    void Function(List<int> bytes) onData,
  ) async {
    await chr.setNotifyValue(true);
    chr.lastValueStream.listen(onData);
  }

  MeasurementReading? _parseBloodPressure(List<int> bytes) {
    if (bytes.length < 7) return null;
    final data = Uint8List.fromList(bytes);
    final view = ByteData.sublistView(data);

    final flags = view.getUint8(0);
    final inKpa = (flags & 0x01) != 0;
    final hasHeartRate = (flags & 0x10) != 0;

    final sys = _sfloat(view.getUint16(1, Endian.little));
    final dia = _sfloat(view.getUint16(3, Endian.little));
    final factor = inKpa ? 7.50062 : 1.0;

    int? bpm;
    if (hasHeartRate) {
      final hasTs = (flags & 0x04) != 0;
      final offset = 7 + (hasTs ? 7 : 0);
      if (data.length >= offset + 2) {
        bpm = _sfloat(view.getUint16(offset, Endian.little)).round();
      }
    }

    return MeasurementReading(
      kind: DeviceKind.bloodPressure,
      payload: {
        'systolic': (sys * factor).round(),
        'diastolic': (dia * factor).round(),
        if (bpm != null) 'heartRate': bpm,
      },
      measuredAt: DateTime.now(),
    );
  }

  MeasurementReading? _parseWeight(List<int> bytes) {
    if (bytes.length < 3) return null;
    final data = Uint8List.fromList(bytes);
    final view = ByteData.sublistView(data);

    final flags = view.getUint8(0);
    final inLb = (flags & 0x01) != 0;
    final raw = view.getUint16(1, Endian.little);
    final weight = inLb ? raw * 0.01 * 0.4536 : raw * 0.005;

    if (weight <= 5 || weight > 250) return null;
    return MeasurementReading(
      kind: DeviceKind.weightScale,
      payload: {'weightKg': double.parse(weight.toStringAsFixed(2))},
      measuredAt: DateTime.now(),
    );
  }

  MeasurementReading? _parseHeartRate(List<int> bytes) {
    if (bytes.length < 2) return null;
    final flags = bytes[0];
    final isUint16 = (flags & 0x01) != 0;
    final bpm = isUint16
        ? (bytes.length < 3 ? null : bytes[1] | (bytes[2] << 8))
        : bytes[1];
    if (bpm == null || bpm <= 0 || bpm > 250) return null;
    return MeasurementReading(
      kind: DeviceKind.heartRate,
      payload: {'bpm': bpm},
      measuredAt: DateTime.now(),
    );
  }

  double _sfloat(int raw) {
    final mantissaRaw = raw & 0x0FFF;
    final exponentRaw = (raw >> 12) & 0x0F;
    final mantissa = mantissaRaw >= 0x0800 ? mantissaRaw - 0x1000 : mantissaRaw;
    final exponent = exponentRaw >= 0x08 ? exponentRaw - 0x10 : exponentRaw;
    return mantissa * _pow10(exponent);
  }

  double _pow10(int e) {
    if (e == 0) return 1.0;
    var result = 1.0;
    for (var i = 0; i < e.abs(); i++) {
      result *= e > 0 ? 10 : 0.1;
    }
    return result;
  }
}
