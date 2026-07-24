import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/sync/sync_service.dart';

class KeySetupPage extends StatefulWidget {
  const KeySetupPage({super.key});

  @override
  State<KeySetupPage> createState() => _KeySetupPageState();
}

class _KeySetupPageState extends State<KeySetupPage> {
  final KeyVault _vault = sl<KeyVault>();
  final _restoreController = TextEditingController();

  Uint8List? _umk;
  String? _mnemonic;
  bool _confirmed = false;
  bool _backedUp = false;
  bool _busy = false;
  String? _restoreMnemonicError;
  String? _restoreStatusMessage;
  bool _restoreStatusError = false;
  Timer? _clipboardClearTimer;

  @override
  void initState() {
    super.initState();
    _refreshBackupState();
  }

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    _restoreController.dispose();
    super.dispose();
  }

  Future<void> _refreshBackupState() async {
    final backed = await _vault.isBackedUp();
    if (!mounted) return;
    setState(() => _backedUp = backed);
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/sync');
    }
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _restoreMnemonicError = null;
    });
    try {
      final umk = await _vault.generate();
      final mnemonic = _vault.exportMnemonic(umk);
      await sl<SyncService>().prepareForKeyChange();
      if (!mounted) return;
      setState(() {
        _umk = umk;
        _mnemonic = mnemonic;
        _confirmed = false;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restore() async {
    final text = _restoreController.text.trim();
    if (text.isEmpty) {
      setState(() => _restoreMnemonicError = '请输入助记词');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _restoreMnemonicError = null;
      _restoreStatusMessage = '正在校验助记词并写入本地安全存储...';
      _restoreStatusError = false;
    });
    try {
      final umk = await _vault.restoreFromMnemonic(text);
      if (!mounted) return;
      setState(() {
        _umk = umk;
        _mnemonic = _vault.exportMnemonic(umk);
        _confirmed = true;
        _restoreStatusMessage = '主密钥已写入本地，正在检查云同步权限...';
      });
      await _vault.markBackedUp();
      await sl<SyncService>().prepareForKeyChange();
      sl<HealthRepository>().signalChanged();
      await _refreshBackupState();

      if (!mounted) return;
      final syncService = sl<SyncService>();
      await syncService.setSyncEnabled(true);
      final result = await syncService.sync();
      if (!mounted) return;
      if (result.hasError) {
        throw StateError(result.error ?? '同步失败');
      }
      final message = '主密钥已恢复，已合并本机与云端全部数据：'
          '上传 ${result.pushed} 条，拉取 ${result.pulled} 条。';
      setState(() {
        _restoreStatusMessage = message;
        _restoreStatusError = false;
      });
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _restoreMnemonicError = _friendlyRestoreError(e);
        _restoreStatusMessage = _friendlyRestoreError(e);
        _restoreStatusError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copy() async {
    if (_mnemonic == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _mnemonic!));
    _clipboardClearTimer?.cancel();
    final copied = _mnemonic!;
    _clipboardClearTimer = Timer(const Duration(seconds: 60), () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == copied) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('助记词已复制到剪贴板，请立即离线保存')));
  }

  Future<void> _markBackedUp() async {
    if (!_confirmed) return;
    final messenger = ScaffoldMessenger.of(context);
    await _vault.markBackedUp();
    sl<HealthRepository>().signalChanged();
    await _refreshBackupState();
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('已确认备份，可以开启云同步')));
  }

  String _friendlyRestoreError(Object e) {
    final text = e.toString();
    if (text.contains('助记词') || text.contains('Mnemonic')) {
      return '助记词不匹配，请核对';
    }
    if (text.contains('本地存储') ||
        text.contains('secure storage') ||
        text.contains('KeyStore') ||
        text.contains('Keychain')) {
      return '本地存储异常，无法恢复密钥';
    }
    return text.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: '返回',
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('云同步与密钥'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StatusBanner(backedUp: _backedUp),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final generatePanel = _Panel(
                title: '生成主密钥',
                subtitle: '首次开通云同步时使用',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '系统会在本地生成 32 字节 UMK，并写入安全存储。服务端始终只看到密文。',
                      style: TextStyle(color: AppTheme.muted, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _busy ? null : _generate,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.vpn_key_outlined),
                      label: Text(_umk == null ? '生成主密钥' : '重新生成主密钥'),
                    ),
                  ],
                ),
              );

              final backupPanel = _Panel(
                title: '助记词备份',
                subtitle: '请离线抄写，丢失后无法恢复云端密文',
                child: _mnemonic == null
                    ? const _EmptyState(text: '生成主密钥后，助记词会显示在这里。')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.lock_outline, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'BIP39 助记词',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: '复制',
                                onPressed: _copy,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final word in _mnemonic!.split(' '))
                                Chip(label: Text(word)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            value: _confirmed,
                            onChanged: (value) =>
                                setState(() => _confirmed = value ?? false),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('我已离线备份助记词'),
                            subtitle: const Text(
                              '· 服务端和客服无法找回\n· 丢失后云端敏感数据将不可恢复',
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _confirmed ? _markBackedUp : null,
                              child: const Text('确认已备份'),
                            ),
                          ),
                        ],
                      ),
              );

              final restorePanel = _Panel(
                title: '恢复主密钥',
                subtitle: '更换设备或重装后使用',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _restoreController,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: '输入助记词',
                        hintText: '24 个单词，空格分隔',
                        errorText: _restoreMnemonicError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_restoreStatusMessage != null) ...[
                      _RestoreStatusCard(
                        message: _restoreStatusMessage!,
                        isError: _restoreStatusError,
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _restore,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.restore_outlined),
                        label: Text(_busy ? '恢复中...' : '恢复到本地'),
                      ),
                    ),
                  ],
                ),
              );

              if (wide) {
                return Column(
                  children: [
                    generatePanel,
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: backupPanel),
                        const SizedBox(width: 16),
                        Expanded(child: restorePanel),
                      ],
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  generatePanel,
                  const SizedBox(height: 16),
                  backupPanel,
                  const SizedBox(height: 16),
                  restorePanel,
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            '最近更新：${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.backedUp});

  final bool backedUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: backedUp ? Colors.green.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: backedUp ? Colors.green.shade200 : AppTheme.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            backedUp ? Icons.verified_outlined : Icons.info_outline,
            color: backedUp ? Colors.green.shade700 : AppTheme.deepBlue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              backedUp ? '主密钥已备份，云端同步可用。' : '尚未完成主密钥备份，生成后请先离线保存助记词，再开启云同步。',
              style: const TextStyle(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _RestoreStatusCard extends StatelessWidget {
  const _RestoreStatusCard({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red.shade700 : Colors.green.shade700;
    final bg = isError ? Colors.red.shade50 : Colors.green.shade50;
    final border = isError ? Colors.red.shade100 : Colors.green.shade100;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text,
          style: const TextStyle(color: AppTheme.muted, height: 1.5)),
    );
  }
}
