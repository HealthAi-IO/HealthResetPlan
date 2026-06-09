import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/bluetooth/bluetooth_service.dart';
import '../../core/data/device_models.dart';
import '../../core/data/device_repository.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';

class DeviceScanPage extends StatefulWidget {
  const DeviceScanPage({super.key});

  @override
  State<DeviceScanPage> createState() => _DeviceScanPageState();
}

class _DeviceScanPageState extends State<DeviceScanPage> {
  final BluetoothService _bt = sl<BluetoothService>();
  final DeviceRepository _devRepo = sl<DeviceRepository>();
  final HealthRepository _healthRepo = sl<HealthRepository>();

  List<ScannedDevice> _results = [];
  StreamSubscription? _scanSub;
  bool _scanning = false;
  String? _statusText;
  int? _connectingIndex;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _bt.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _statusText = '正在准备…';
      _results = [];
    });

    // 1) 权限
    final granted = await _bt.ensurePermissions();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _statusText = '蓝牙或定位权限被拒绝，请到系统设置中开启';
      });
      return;
    }

    // 2) 蓝牙开关
    if (!await _bt.isBluetoothOn()) {
      await _bt.turnOn();
      await Future.delayed(const Duration(milliseconds: 500));
      if (!await _bt.isBluetoothOn()) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _statusText = '请先打开手机蓝牙';
        });
        return;
      }
    }

    setState(() => _statusText = '正在扫描附近设备…');

    // 3) 启动扫描
    _scanSub?.cancel();
    _scanSub = _bt.scan().listen(
      (list) {
        if (!mounted) return;
        setState(() => _results = list);
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _statusText = _results.isEmpty
              ? '未发现设备，请确认设备已开启并靠近手机'
              : '扫描完成，找到 ${_results.length} 个设备';
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _statusText = '扫描出错：$e';
        });
      },
    );
  }

  Future<void> _connectAndBind(ScannedDevice d, int index) async {
    if (d.isWearableBand) {
      await _bindWearableBand(d, index);
      return;
    }

    if (d.inferredKind == DeviceKind.unknown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂未识别该设备类型，请选择体脂秤、血压计、心率设备或手环手表')),
      );
      return;
    }

    if (!d.connectable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该设备当前不可连接，请唤醒设备或进入测量/配对模式后重试')),
      );
      return;
    }

    setState(() => _connectingIndex = index);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _bt.stopScan();
      _scanSub?.cancel();

      messenger.showSnackBar(SnackBar(content: Text('正在连接 ${d.name}…')));

      final stream = await _bt.connectAndSubscribe(d.id);

      // 持久化绑定
      final boundId = await _devRepo.bind(
        kind: d.inferredKind,
        name: d.name,
        macAddress: d.id,
        syncSource: DeviceSyncSource.bleLive,
      );

      // 监听首次数据（演示），收到一条就更新 last_sync
      stream.listen((reading) async {
        // 把测量数据写入 health_indicator
        await _healthRepo.addIndicator(
          type: _indicatorType(reading.kind),
          payload: reading.payload,
          source: 'bluetooth',
          measuredAt: reading.measuredAt,
        );
        if (reading.payload['bodyFatPct'] is num) {
          await _healthRepo.addIndicator(
            type: 'body_fat',
            payload: {'bodyFatPct': reading.payload['bodyFatPct']},
            source: 'bluetooth',
            measuredAt: reading.measuredAt,
          );
        }
        await _devRepo.updateLastSync(boundId);
      });

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('「${d.name}」绑定成功'),
          backgroundColor: Colors.green,
        ),
      );
      // 返回设备列表页
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _connectingIndex = null);
      messenger.showSnackBar(
        SnackBar(
          content: Text('连接失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _bindWearableBand(ScannedDevice d, int index) async {
    setState(() => _connectingIndex = index);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _bt.stopScan();
      _scanSub?.cancel();

      final existing = await _devRepo.findByMac(d.id);
      if (existing != null) {
        messenger.showSnackBar(SnackBar(content: Text('「${d.name}」已绑定')));
        if (mounted) context.pop();
        return;
      }

      final standardKind = await _discoverBandStandardKind(d);
      if (standardKind != DeviceKind.unknown) {
        await _devRepo.bind(
          kind: standardKind,
          name: d.name,
          macAddress: d.id,
          brand: _inferBandBrand(d.name),
          syncSource: DeviceSyncSource.bleLive,
        );

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('「${d.name}」支持标准 BLE，已绑定为蓝牙实时采集设备'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
        return;
      }

      await _devRepo.bind(
        kind: DeviceKind.band,
        name: d.name,
        macAddress: d.id,
        brand: _inferBandBrand(d.name),
        syncSource: DeviceSyncSource.systemHealth,
      );

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('已绑定「${d.name}」。该手环未开放标准 BLE 数据，需通过系统健康同步'),
          backgroundColor: Colors.green,
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _connectingIndex = null);
      messenger.showSnackBar(
        SnackBar(
          content: Text('绑定失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _indicatorType(DeviceKind kind) => switch (kind) {
        DeviceKind.bloodPressure => 'bp',
        DeviceKind.weightScale => 'weight',
        DeviceKind.heartRate => 'heart_rate',
        DeviceKind.band => 'heart_rate',
        _ => 'other',
      };

  Future<DeviceKind> _discoverBandStandardKind(ScannedDevice device) async {
    if (!device.connectable) return DeviceKind.unknown;
    try {
      return await _bt.discoverSupportedMeasurementKind(device.id);
    } catch (_) {
      return DeviceKind.unknown;
    }
  }

  String _inferBandBrand(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('huawei')) return '华为';
    if (normalized.contains('honor')) return '荣耀';
    if (normalized.contains('mi') || normalized.contains('xiaomi')) return '小米';
    if (normalized.contains('apple')) return 'Apple';
    return '手环/手表';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBg,
      appBar: AppBar(
        title: const Text('扫描设备'),
        actions: [
          IconButton(
            tooltip: _scanning ? '停止扫描' : '重新扫描',
            icon: Icon(_scanning ? Icons.stop : Icons.refresh),
            onPressed: () async {
              if (_scanning) {
                await _bt.stopScan();
                _scanSub?.cancel();
                if (!mounted) return;
                setState(() => _scanning = false);
              } else {
                _startScan();
              }
            },
          ),
        ],
      ),
      body: Column(children: [
        _buildStatusBar(),
        Expanded(
          child: _results.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () async => _startScan(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _DeviceRow(
                      device: _results[i],
                      connecting: _connectingIndex == i,
                      onTap: () => _connectAndBind(_results[i], i),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      color: _scanning
          ? AppTheme.deepBlue.withValues(alpha: 0.08)
          : Colors.transparent,
      child: Row(children: [
        if (_scanning) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
        ] else
          const Icon(Icons.info_outline, size: 16, color: AppTheme.muted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _statusText ?? '',
            style: const TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
        ),
      ]),
    );
  }

  Widget _buildEmptyState() {
    if (_scanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching,
                size: 48, color: AppTheme.deepBlue.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            const Text('正在搜索附近的蓝牙设备…', style: TextStyle(color: AppTheme.muted)),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('暂未发现设备', style: TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 6),
            const Text(
              '请打开设备电源，靠近手机后点击右上角刷新',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.connecting,
    required this.onTap,
  });

  final ScannedDevice device;
  final bool connecting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = device.inferredKind;
    return GestureDetector(
      onTap: connecting ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.deepBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(kind.emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(device.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                '${kind.label} · ${_syncModeText(device)} · 信号 ${device.rssi} dBm',
                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
              ),
            ]),
          ),
          if (connecting)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.add_circle_outline, color: AppTheme.deepBlue),
        ]),
      ),
    );
  }

  String _syncModeText(ScannedDevice device) {
    if (device.isWearableBand) return '系统健康同步';
    if (device.hasStandardBleMeasurement) return 'BLE 实时采集';
    return device.connectable ? '可连接' : '不可连接';
  }
}
