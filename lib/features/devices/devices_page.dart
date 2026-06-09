import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/bluetooth/bluetooth_service.dart';
import '../../core/data/device_models.dart';
import '../../core/data/device_repository.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/sync/health_sync_bridge.dart';
import '../../core/sync/sync_service.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final DeviceRepository _repo = sl<DeviceRepository>();
  final SyncService _syncService = sl<SyncService>();
  final BluetoothService _bt = sl<BluetoothService>();
  final HealthRepository _healthRepo = sl<HealthRepository>();

  List<BoundDevice> _devices = [];
  bool _loading = true;
  int? _syncingId;
  bool? _bluetoothOn;
  HealthAccessStatus? _healthAccess;
  bool _authorizingHealth = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final devicesFuture = _repo.listBound();
    final bluetoothFuture = _loadBluetoothOn();
    final healthAccessFuture = _loadHealthAccess();

    try {
      final devices = await devicesFuture;
      final bluetoothOn = await bluetoothFuture;
      final healthAccess = await healthAccessFuture;
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _bluetoothOn = bluetoothOn;
        _healthAccess = healthAccess;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('设备状态加载失败：$e', error: true);
    }
  }

  Future<bool?> _loadBluetoothOn() async {
    try {
      return await _bt.isBluetoothOn();
    } catch (_) {
      return null;
    }
  }

  Future<HealthAccessStatus?> _loadHealthAccess() async {
    try {
      return await _syncService.healthSyncBridge.accessStatus();
    } catch (_) {
      return null;
    }
  }

  Future<void> _bindSystemHealthBand() async {
    final existing = await _repo.findByMac('system-health');
    if (existing != null) {
      _showSnack('系统健康手环已绑定');
      return;
    }

    final access = await _requestSystemHealthAccess();
    if (access == null) return;
    if (!access.anyGranted) {
      _showSnack('未获得任何健康数据读取权限', error: true);
      return;
    }

    await _repo.bind(
      kind: DeviceKind.band,
      name: '系统健康手环/手表',
      macAddress: 'system-health',
      brand: '小米 / 华为 / Apple / Health Connect',
      syncSource: DeviceSyncSource.systemHealth,
    );
    await _load();
    _showSnack('已绑定系统健康数据源');
  }

  Future<HealthAccessStatus?> _requestSystemHealthAccess() async {
    if (_authorizingHealth) return null;
    if (mounted) setState(() => _authorizingHealth = true);

    try {
      final access = await _syncService.healthSyncBridge.requestAccess();
      if (mounted) setState(() => _healthAccess = access);
      return access;
    } catch (e) {
      _showSnack('系统健康授权失败：$e', error: true);
      return null;
    } finally {
      if (mounted) setState(() => _authorizingHealth = false);
    }
  }

  Future<void> _syncDevice(BoundDevice device) async {
    setState(() => _syncingId = device.id);
    await _repo.updateSyncState(device.id, syncState: 'syncing');

    SyncResult result;
    if (device.syncSource == DeviceSyncSource.systemHealth) {
      result = await _syncService.syncSystemHealth();
    } else if (device.syncSource == DeviceSyncSource.bleLive) {
      result = await _syncBleDevice(device);
    } else {
      result = const SyncResult(
        pushed: 0,
        pulled: 0,
        error: '请在设备测量时保持连接，BLE 数据会自动写入',
      );
    }

    if (result.hasError) {
      await _repo.updateSyncState(
        device.id,
        syncState: 'error',
        lastError: result.error ?? '',
      );
      _showSnack(result.error ?? '同步失败', error: true);
    } else {
      await _repo.updateLastSync(device.id);
      _showSnack('已同步 ${result.pushed} 条健康数据');
    }

    if (!mounted) return;
    setState(() => _syncingId = null);
    await _load();
  }

  Future<SyncResult> _syncBleDevice(BoundDevice device) async {
    try {
      final granted = await _bt.ensurePermissions();
      if (!granted) {
        return const SyncResult(
          pushed: 0,
          pulled: 0,
          error: '蓝牙权限未开启，请到系统设置中允许蓝牙/定位权限',
        );
      }

      if (!await _bt.isBluetoothOn()) {
        await _bt.turnOn();
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (!await _bt.isBluetoothOn()) {
        return const SyncResult(pushed: 0, pulled: 0, error: '请先打开手机蓝牙');
      }

      final readings = await _bt.collectMeasurements(device.macAddress);
      if (readings.isEmpty) {
        return const SyncResult(
          pushed: 0,
          pulled: 0,
          error: '已连接设备，但未收到测量数据。请佩戴手环并开启心率测量后重试',
        );
      }

      var inserted = 0;
      for (final reading in readings) {
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
        inserted++;
      }
      return SyncResult(pushed: inserted, pulled: 0);
    } catch (e) {
      return SyncResult(pushed: 0, pulled: 0, error: _formatBleSyncError(e));
    }
  }

  String _indicatorType(DeviceKind kind) => switch (kind) {
        DeviceKind.bloodPressure => 'bp',
        DeviceKind.weightScale => 'weight',
        DeviceKind.heartRate || DeviceKind.band => 'heart_rate',
        _ => 'other',
      };

  String _formatBleSyncError(Object error) {
    final text = '$error';
    if (text.contains('标准 BLE 健康测量服务')) {
      return '该手环没有开放标准 BLE 健康数据。华为手环通常需要先同步到华为运动健康，再通过系统健康通道导入 App';
    }
    if (text.contains('connection') || text.contains('GATT')) {
      return '蓝牙连接失败，请确认设备靠近手机、未被其他 App 占用，并处于可连接状态';
    }
    return text;
  }

  Future<void> _unbind(BoundDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解绑设备'),
        content: Text('确定要解绑「${d.name}」吗？\n历史采集的数据不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.unbind(d.id);
    if (!mounted) return;
    await _load();
    _showSnack('已解绑「${d.name}」');
  }

  void _showSnack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBg,
      appBar: AppBar(
        title: const Text('我的设备'),
        actions: [
          IconButton(
            tooltip: '添加设备',
            icon: const Icon(Icons.add),
            onPressed: () async {
              await context.push('/devices/scan');
              if (mounted) _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_devices.isEmpty) _buildEmptyState(),
                  _buildSyncStatusPanel(),
                  const SizedBox(height: 12),
                  for (final d in _devices) ...[
                    _DeviceCard(
                      device: d,
                      syncing: _syncingId == d.id,
                      onSync: () => _syncDevice(d),
                      onUnbind: () => _unbind(d),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildActionCard(
                    icon: Icons.bluetooth_searching,
                    title: '扫描添加 BLE 设备',
                    subtitle: '体脂秤、血压计、标准心率设备会在测量时自动入库',
                    onTap: () async {
                      await context.push('/devices/scan');
                      if (mounted) _load();
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildActionCard(
                    icon: Icons.health_and_safety_outlined,
                    title: '绑定小米 / 华为 / 手环手表',
                    subtitle: '通过系统健康通道同步步数、心率、睡眠',
                    onTap: _bindSystemHealthBand,
                  ),
                  const SizedBox(height: 16),
                  _buildCapabilityNote(),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Icon(Icons.bluetooth_searching,
              size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('暂无绑定设备',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          const Text(
            '体脂秤、血压计走蓝牙采集\n手环手表走系统健康同步',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(children: [
          Icon(icon, color: AppTheme.deepBlue),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.muted),
        ]),
      ),
    );
  }

  Widget _buildSyncStatusPanel() {
    final healthAccess = _healthAccess;
    final healthStatus = healthAccess == null
        ? '状态未知'
        : (!healthAccess.available
            ? '未安装或不可用'
            : (healthAccess.anyGranted ? '已授权部分数据' : '未授权'));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.sync_alt, color: AppTheme.deepBlue),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('同步状态',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('刷新'),
          ),
        ]),
        const SizedBox(height: 10),
        _StatusLine(
          icon: Icons.bluetooth,
          title: '蓝牙采集',
          value: _bluetoothOn == null
              ? '状态未知'
              : (_bluetoothOn! ? '蓝牙已开启' : '蓝牙未开启'),
          ok: _bluetoothOn == true,
        ),
        const SizedBox(height: 8),
        _StatusLine(
          icon: Icons.health_and_safety_outlined,
          title: '系统健康同步',
          value: healthStatus,
          ok: healthAccess?.anyGranted == true,
        ),
        if (healthAccess != null && healthAccess.available) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PermissionChip(label: '步数', granted: healthAccess.stepsGranted),
              _PermissionChip(
                  label: '心率', granted: healthAccess.heartRateGranted),
              _PermissionChip(label: '睡眠', granted: healthAccess.sleepGranted),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _authorizingHealth
                ? null
                : () async {
                    final access = await _requestSystemHealthAccess();
                    if (access == null) return;
                    _showSnack(
                        access.anyGranted ? '系统健康权限已更新' : '未获得系统健康数据读取权限');
                  },
            icon: const Icon(Icons.verified_user_outlined, size: 16),
            label: Text(_authorizingHealth ? '授权中...' : '授权系统健康数据'),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          '标准 BLE 设备可直接采集；华为手环若未开放标准 BLE 数据，请先同步到华为运动健康，再通过系统健康通道导入。',
          style: TextStyle(fontSize: 11, color: AppTheme.muted, height: 1.5),
        ),
      ]),
    );
  }

  Widget _buildCapabilityNote() {
    final items = [
      (
        DeviceKind.weightScale.emoji,
        '体脂秤 / 体重秤',
        'BLE Weight Scale / Body Composition'
      ),
      (DeviceKind.bloodPressure.emoji, '血压计', 'BLE Blood Pressure'),
      (DeviceKind.heartRate.emoji, '心率设备', 'BLE Heart Rate'),
      (
        DeviceKind.band.emoji,
        '小米 / 华为 / Apple 手环手表',
        'Health Connect / HealthKit'
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('已接入能力',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 10),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Text(item.$1, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.$2, style: const TextStyle(fontSize: 13)),
                      Text(item.$3,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.muted)),
                    ]),
              ),
              Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
            ]),
          ),
      ]),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.syncing,
    required this.onSync,
    required this.onUnbind,
  });

  final BoundDevice device;
  final bool syncing;
  final VoidCallback onSync;
  final VoidCallback onUnbind;

  @override
  Widget build(BuildContext context) {
    final lastSync = device.lastSyncAt == 0
        ? '从未同步'
        : DateFormat('MM-dd HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(device.lastSyncAt));
    final status = device.syncState == 'error' && device.lastError.isNotEmpty
        ? device.lastError
        : '${device.syncSource.label} · 上次同步 $lastSync';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.deepBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(device.kind.emoji, style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(device.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              '${device.kind.label} · $status',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color:
                    device.syncState == 'error' ? Colors.red : AppTheme.muted,
              ),
            ),
          ]),
        ),
        IconButton(
          tooltip: '同步',
          icon: syncing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync, size: 18),
          onPressed: syncing ? null : onSync,
        ),
        IconButton(
          tooltip: '解绑',
          icon: Icon(Icons.link_off, size: 18, color: Colors.grey.shade500),
          onPressed: onUnbind,
        ),
      ]),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.title,
    required this.value,
    required this.ok,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.green.shade600 : AppTheme.muted;
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    ]);
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({
    required this.label,
    required this.granted,
  });

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final color = granted ? Colors.green.shade600 : Colors.orange.shade700;
    final bg = granted ? Colors.green.shade50 : Colors.orange.shade50;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          granted ? Icons.check_circle : Icons.info_outline,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ]),
    );
  }
}
