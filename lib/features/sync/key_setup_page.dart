import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Uint8List 通过 flutter/services 间接提供。

import '../../core/crypto/key_vault.dart';
import '../../core/di/service_locator.dart';

/// 云同步 / 密钥设置页：生成 UMK、展示助记词、要求用户确认备份。
class KeySetupPage extends StatefulWidget {
  const KeySetupPage({super.key});

  @override
  State<KeySetupPage> createState() => _KeySetupPageState();
}

class _KeySetupPageState extends State<KeySetupPage> {
  Uint8List? _umk;
  String? _mnemonic;
  bool _confirmed = false;
  bool _backedUp = false;

  KeyVault get _vault => sl<KeyVault>();

  @override
  void initState() {
    super.initState();
    _refreshBackupState();
  }

  Future<void> _refreshBackupState() async {
    final backed = await _vault.isBackedUp();
    if (!mounted) return;
    setState(() => _backedUp = backed);
  }

  Future<void> _generate() async {
    final umk = await _vault.generate();
    final mnemonic = _vault.exportMnemonic(umk);
    setState(() {
      _umk = umk;
      _mnemonic = mnemonic;
      _confirmed = false;
    });
  }

  Future<void> _copy() async {
    if (_mnemonic == null) return;
    await Clipboard.setData(ClipboardData(text: _mnemonic!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('助记词已复制到剪贴板，请立即妥善保存')),
    );
  }

  Future<void> _markBackedUp() async {
    if (!_confirmed) return;
    await _vault.markBackedUp();
    await _refreshBackupState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已确认备份，您可以开启端到端加密云同步了')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('云同步 · 端到端加密')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _NoticeCard(backedUp: _backedUp),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.vpn_key),
            label: Text(_umk == null ? '生成主密钥' : '重新生成主密钥'),
            onPressed: _generate,
          ),
          if (_mnemonic != null) ...[
            const SizedBox(height: 16),
            _MnemonicCard(mnemonic: _mnemonic!, onCopy: _copy),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _confirmed,
              onChanged: (v) => setState(() => _confirmed = v ?? false),
              title: const Text('我已抄写 / 离线备份助记词，并理解：'),
              subtitle: const Text(
                '· 助记词等同于云端数据的钥匙\n'
                '· 服务端 / 客服 无法找回助记词\n'
                '· 丢失助记词将永久失去云端敏感数据',
              ),
            ),
            FilledButton(
              onPressed: _confirmed ? _markBackedUp : null,
              child: const Text('确认已备份，开启云同步'),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.backedUp});
  final bool backedUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backedUp ? Colors.green.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: backedUp ? Colors.green : Colors.amber,
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            backedUp ? Icons.shield_outlined : Icons.warning_amber_outlined,
            color: backedUp ? Colors.green : Colors.amber.shade800,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              backedUp
                  ? '主密钥已备份，云端敏感数据将通过 AES-256-GCM 端到端加密。'
                  : '尚未生成或未确认备份主密钥。生成后请立即抄写助记词，妥善保管！',
            ),
          ),
        ],
      ),
    );
  }
}

class _MnemonicCard extends StatelessWidget {
  const _MnemonicCard({required this.mnemonic, required this.onCopy});
  final String mnemonic;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final words = mnemonic.split(' ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: 8),
              const Text(
                'BIP39 助记词（请离线抄写）',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: '复制',
                onPressed: onCopy,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < words.length; i++)
                Chip(label: Text('${i + 1}. ${words[i]}')),
            ],
          ),
        ],
      ),
    );
  }
}
