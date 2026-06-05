import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/device_models.dart';
import '../../core/data/device_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/sync/sync_service.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final DeviceRepository _repo = sl<DeviceRepository>();
  final SyncService _syncService = sl<SyncService>();

  List<BoundDevice> _devices = [];
  bool _loading = true;
  int? _syncingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _repo.listBound();
    if (!mounted) return;
    setState(() {
      _devices = list;
      _loading = false;
    });
  }

  Future<void> _bindSystemHealthBand() async {
    final existing = await _repo.findByMac('system-health');
    if (existing != null) {
      _showSnack('系统健康手环已绑定');
      return;
    }

    final allowed = await _syncService.healthSyncBridge.requestAccess();
    if (!allowed) {
      _showSnack('未获得健康数据读取权限', error: true);
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

  Future<void> _syncDevice(BoundDevice device) async {
    setState(() => _syncingId = device.id);
    await _repo.updateSyncState(device.id, syncState: 'syncing');

    SyncResult result;
    if (device.syncSource == DeviceSyncSource.systemHealth ||
        device.kind == DeviceKind.band) {
      result = await _syncService.syncSystemHealth();
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
          Icon(Icons.bluetooth_searching, size: 48, color: Colors.grey.shade400),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
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

  Widget _buildCapabilityNote() {
    final items = [
      (DeviceKind.weightScale.emoji, '体脂秤 / 体重秤', 'BLE Weight Scale / Body Composition'),
      (DeviceKind.bloodPressure.emoji, '血压计', 'BLE Blood Pressure'),
      (DeviceKind.heartRate.emoji, '心率设备', 'BLE Heart Rate'),
      (DeviceKind.band.emoji, '小米 / 华为 / Apple 手环手表', 'Health Connect / HealthKit'),
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.$2, style: const TextStyle(fontSize: 13)),
                  Text(item.$3,
                      style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(device.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              '${device.kind.label} · $status',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: device.syncState == 'error' ? Colors.red : AppTheme.muted,
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

