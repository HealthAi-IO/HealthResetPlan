import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/alipay_pay_service.dart';
import '../../core/membership/membership_service.dart';
import '../../core/membership/wechat_pay_service.dart';
import '../../core/sync/sync_service.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  final MembershipService _service = sl<MembershipService>();

  MembershipStatus _status = MembershipStatus.free;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await _service.getStatus(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _openPlan({
    required String planCode,
    required String planName,
  }) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActivationSheet(
        planCode: planCode,
        planName: planName,
        onRedeem: (code) async {
          if (code.trim().isEmpty) return '请输入激活码';
          try {
            await _service.activateWithCode(code);
            return null;
          } catch (e) {
            return _friendly(e);
          }
        },
        onWechatPay: () async {
          try {
            await _payWithWechat(planCode);
            return null;
          } catch (e) {
            return _friendly(e);
          }
        },
        onAlipay: () async {
          try {
            await _payWithAlipay(planCode);
            return null;
          } catch (e) {
            return _friendly(e);
          }
        },
      ),
    );

    if (confirmed == true) {
      await _handleActivationSuccess('会员权益已开通');
    }
  }

  Future<void> _payWithWechat(String planCode) async {
    final order = await _service.createOrder(planCode: planCode);
    if (order.payCredential.isEmpty) {
      throw StateError('微信支付参数为空');
    }
    await sl<WechatPayService>().pay(order.payCredential);
    await Future<void>.delayed(const Duration(seconds: 2));
    _service.invalidateCache();
  }

  Future<void> _payWithAlipay(String planCode) async {
    final order = await _service.createOrder(
      planCode: planCode,
      channel: 'alipay',
    );
    if (order.payCredential.isEmpty) {
      throw StateError('支付宝支付参数为空');
    }
    await sl<AlipayPayService>().pay(order.payCredential);
    await Future<void>.delayed(const Duration(seconds: 2));
    _service.invalidateCache();
  }

  Future<void> _handleActivationSuccess(String message) async {
    final shouldPromptRestoreKey = await _syncLocalData();
    if (!mounted) return;
    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );

    if (!shouldPromptRestoreKey) return;
    final restoreNow = await _showRestoreKeyDialog();
    if (!mounted) return;
    if (restoreNow == true) {
      await context.push('/sync/key-setup');
      if (!mounted) return;
      await _load();
    }
  }

  Future<bool> _syncLocalData() async {
    try {
      final sync = sl<SyncService>();
      await sync.setSyncEnabled(true);
      final umk = await sl<KeyVault>().readUmk();
      if (umk == null) return true;
      final result = await sync.sync();
      return result.hasError && _isKeyRestoreRequired(result.error);
    } catch (_) {
      return false;
    }
  }

  bool _isKeyRestoreRequired(String? error) {
    final text = error ?? '';
    return text.contains('主密钥') ||
        text.contains('助记词') ||
        text.contains('密钥异常') ||
        text.contains('UMK');
  }

  Future<bool?> _showRestoreKeyDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要恢复云端密钥'),
        content: const Text('会员权益已开通，但这台设备还没有恢复云同步密钥。是否现在去恢复？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('现在恢复'),
          ),
        ],
      ),
    );
  }

  String _friendly(Object e) {
    if (e is StateError) return e.message;
    if (e is DioException) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      if (body is Map) {
        final msg = body['message']?.toString() ?? body['msg']?.toString();
        if (msg != null && msg.isNotEmpty) return msg;
      }
      if (status == 401) return '登录已过期，请重新登录';
      if (status == 403) return '请先登录账号';
      if (status != null && status >= 500) return '服务器错误（$status）';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return '请求超时，请重试';
      }
      return '网络错误，请重试';
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会员中心')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _StatusCard(status: _status),
                const SizedBox(height: 20),
                const Text(
                  '选择套餐',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _PlanCard(
                  title: '年度会员',
                  price: '¥0.01',
                  subtitle: '测试价，正式上线后恢复 ¥28 / 年',
                  recommended: true,
                  onTap: () => _openPlan(
                    planCode: 'yearly',
                    planName: '年度会员',
                  ),
                ),
                const SizedBox(height: 12),
                _PlanCard(
                  title: '月度会员',
                  price: '¥0.01',
                  subtitle: '测试价，正式上线后恢复 ¥2.8 / 月',
                  recommended: false,
                  onTap: () => _openPlan(
                    planCode: 'monthly',
                    planName: '月度会员',
                  ),
                ),
                const SizedBox(height: 20),
                _PromoCodeEntry(
                  onActivate: (code) async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await _service.activateWithCode(code);
                      await _handleActivationSuccess('激活成功，会员权益已开通');
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(_friendly(e)),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final MembershipStatus status;

  @override
  Widget build(BuildContext context) {
    final active = status.isActive;
    final title = active ? status.planName ?? '会员版' : '免费版';
    final subtitle = active && status.expiresAt != null
        ? '有效期至 ${DateFormat('yyyy/MM/dd').format(status.expiresAt!)}'
        : '开通会员后可使用云同步、报告 OCR 和无限 AI 方案';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: active ? AppTheme.deepBlue : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: active ? AppTheme.deepBlue : AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.workspace_premium : Icons.person_outline,
            color: active ? Colors.white : AppTheme.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: active ? Colors.white : AppTheme.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: active ? Colors.white70 : AppTheme.muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.subtitle,
    required this.recommended,
    required this.onTap,
  });

  final String title;
  final String price;
  final String subtitle;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: recommended ? AppTheme.deepBlue : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: recommended ? AppTheme.deepBlue : AppTheme.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: recommended ? Colors.white : AppTheme.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (recommended)
                const Text(
                  '推荐',
                  style: TextStyle(
                      color: Colors.amber, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            price,
            style: TextStyle(
              color: recommended ? Colors.white : AppTheme.deepBlue,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: recommended ? Colors.white70 : AppTheme.muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: recommended ? Colors.white : AppTheme.deepBlue,
                foregroundColor: recommended ? AppTheme.deepBlue : Colors.white,
              ),
              child: Text('开通$title'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoCodeEntry extends StatefulWidget {
  const _PromoCodeEntry({required this.onActivate});

  final Future<void> Function(String code) onActivate;

  @override
  State<_PromoCodeEntry> createState() => _PromoCodeEntryState();
}

class _PromoCodeEntryState extends State<_PromoCodeEntry> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() => _busy = true);
    await widget.onActivate(code);
    if (!mounted) return;
    _ctrl.clear();
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: '输入激活码',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('兑换'),
          ),
        ],
      ),
    );
  }
}

class _ActivationSheet extends StatefulWidget {
  const _ActivationSheet({
    required this.planCode,
    required this.planName,
    required this.onRedeem,
    required this.onWechatPay,
    required this.onAlipay,
  });

  final String planCode;
  final String planName;
  final Future<String?> Function(String code) onRedeem;
  final Future<String?> Function() onWechatPay;
  final Future<String?> Function() onAlipay;

  @override
  State<_ActivationSheet> createState() => _ActivationSheetState();
}

class _ActivationSheetState extends State<_ActivationSheet> {
  final _codeCtrl = TextEditingController();
  String? _errorText;
  bool _busy = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    final error = await action();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorText = error;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '开通${widget.planName}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '微信支付当前为测试价，弹出的支付金额应为 ¥0.01。',
                  style: TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onWechatPay),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.payment),
                    label: const Text('微信支付 ¥0.01'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onAlipay),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('支付宝支付 ¥0.01'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('已有激活码？',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: widget.planCode == 'yearly'
                        ? '输入激活码，如 HEALTH365'
                        : '输入激活码，如 HEALTH30',
                    errorText: _errorText,
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                  ),
                  onSubmitted: (_) =>
                      _run(() => widget.onRedeem(_codeCtrl.text)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => widget.onRedeem(_codeCtrl.text)),
                    child: const Text('兑换激活码'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
