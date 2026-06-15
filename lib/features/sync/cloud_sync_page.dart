import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/paywall.dart';
import '../../core/sync/sync_service.dart';

class CloudSyncPage extends StatefulWidget {
  const CloudSyncPage({super.key});

  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  final SyncService _syncService = sl<SyncService>();
  final KeyVault _vault = sl<KeyVault>();

  bool _syncEnabled = false;
  bool _backedUp = false;
  int _lastSyncMs = 0;
  bool _syncing = false;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _syncService.isSyncEnabled();
    final backedUp = await _vault.isBackedUp();
    final lastMs = await _syncService.getLastSyncMs();
    if (!mounted) return;
    setState(() {
      _syncEnabled = enabled;
      _backedUp = backedUp;
      _lastSyncMs = lastMs;
    });
  }

  Future<void> _toggleSync(bool value) async {
    if (value) {
      // 必须先登录账号 + 已开通会员
      if (!mounted) return;
      final ok =
          await requireAccountAndMember(context, PaywallFeature.cloudSync);
      if (!ok) {
        await _load();
        return;
      }

      final backed = await _vault.isBackedUp();
      if (!backed && mounted) {
        final goSetup = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('需要先备份密钥'),
            content: const Text(
              '开启云同步前，请先生成并备份主密钥（UMK）。\n丢失密钥后云端数据将无法恢复。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去备份'),
              ),
            ],
          ),
        );
        if (goSetup == true && mounted) {
          await context.push('/sync/key-setup');
          await _load();
        }
        return;
      }
    }

    await _syncService.setSyncEnabled(value);
    if (!mounted) return;
    setState(() {
      _syncEnabled = value;
      _syncMessage = null;
    });
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });

    final result = await _syncService.sync();
    final lastMs = await _syncService.getLastSyncMs();

    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastSyncMs = lastMs;
      if (result.hasError) {
        _syncMessage = '同步失败：${result.error}';
      } else if (result.pushed == 0 && result.pulled == 0) {
        _syncMessage = '同步完成：云端没有可拉取的新数据，本地也没有待上传数据'
            '${result.attempts > 1 ? '（重试后成功）' : ''}';
      } else {
        _syncMessage = '同步完成：上传 ${result.pushed} 条，拉取 ${result.pulled} 条'
            '${result.attempts > 1 ? '（重试后成功）' : ''}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('云同步')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SyncToggleCard(
            enabled: _syncEnabled,
            lastSyncMs: _lastSyncMs,
            onToggle: _toggleSync,
          ),
          const SizedBox(height: 16),
          _KeyStatusCard(
            backedUp: _backedUp,
            onSetupTap: () async {
              await context.push('/sync/key-setup');
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (_syncEnabled) ...[
            const Text(
              '立即同步会把本机未上传的数据加密上传，并从云端拉取可解密的新数据。',
              style:
                  TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync),
                label: Text(_syncing ? '同步中…' : '立即同步'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_syncMessage != null) _MessageCard(message: _syncMessage!),
          const SizedBox(height: 20),
          const _E2eeNote(),
        ],
      ),
    );
  }
}

class _SyncToggleCard extends StatelessWidget {
  const _SyncToggleCard({
    required this.enabled,
    required this.lastSyncMs,
    required this.onToggle,
  });

  final bool enabled;
  final int lastSyncMs;
  final void Function(bool) onToggle;

  @override
  Widget build(BuildContext context) {
    final lastSync = lastSyncMs == 0
        ? '从未同步'
        : DateFormat('MM-dd HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(lastSyncMs));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_outlined, color: AppTheme.deepBlue),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '云端同步',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            enabled ? '上次同步：$lastSync' : '关闭状态：免费版数据仅保存在本地轻量 SQLite 数据库。',
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          if (!enabled) ...[
            const SizedBox(height: 4),
            const Text(
              '开启后需要有效的云同步会员权益。',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyStatusCard extends StatelessWidget {
  const _KeyStatusCard({
    required this.backedUp,
    required this.onSetupTap,
  });

  final bool backedUp;
  final VoidCallback onSetupTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: backedUp ? Colors.green.shade200 : AppTheme.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            backedUp ? Icons.verified_user_outlined : Icons.key_outlined,
            color: backedUp ? Colors.green.shade700 : AppTheme.muted,
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  backedUp ? '主密钥已备份' : '主密钥未备份',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: backedUp ? Colors.green.shade700 : AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  backedUp
                      ? '密钥安全存储在本设备，换机时可用助记词恢复。'
                      : '请生成主密钥并离线保存助记词，以防止数据丢失。',
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onSetupTap, child: const Text('管理')),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isError = message.startsWith('同步失败');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? Colors.red.shade200 : Colors.green.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red.shade700 : Colors.green.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.red.shade700 : Colors.green.shade700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _E2eeNote extends StatelessWidget {
  const _E2eeNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: AppTheme.deepBlue),
              SizedBox(width: 6),
              Text(
                '端到端加密说明',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppTheme.deepBlue,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '· 所有健康数据在上传前由本地主密钥（UMK）加密\n'
            '· 服务端仅存储密文，无法获取您的健康信息\n'
            '· 主密钥只存在于您的设备，服务方和客服均无法代为恢复',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }
}
