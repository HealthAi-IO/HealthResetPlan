import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/auth_api.dart';

class CancelAccountDialog extends StatefulWidget {
  const CancelAccountDialog({super.key});

  @override
  State<CancelAccountDialog> createState() => _CancelAccountDialogState();
}

class _CancelAccountDialogState extends State<CancelAccountDialog> {
  final phoneController = TextEditingController();
  final codeController = TextEditingController();
  bool sending = false;
  bool cancelling = false;
  String? error;

  @override
  void dispose() {
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  String get phone => phoneController.text.replaceAll(RegExp(r'\D'), '');

  Future<void> sendCode() async {
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => error = '请输入当前账号绑定的完整手机号');
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final result = await sl<AuthApi>().sendCancelAccountCode(phone);
      if (result.debugCode.isNotEmpty) codeController.text = result.debugCode;
    } catch (e) {
      if (mounted) setState(() => error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> cancelAccount() async {
    if (!RegExp(r'^1\d{10}$').hasMatch(phone) ||
        codeController.text.trim().isEmpty) {
      setState(() => error = '请输入绑定手机号和短信验证码');
      return;
    }
    setState(() {
      cancelling = true;
      error = null;
    });
    try {
      await sl<AuthApi>().cancelAccount(
        phone: phone,
        code: codeController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('注销账号'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '注销后有 30 天恢复期，到期后云端数据将彻底删除。请输入绑定手机号并完成短信验证。',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: '绑定手机号'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '短信验证码'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: sending ? null : sendCode,
                    child: Text(sending ? '发送中…' : '获取验证码'),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: cancelling ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: cancelling ? null : cancelAccount,
            child: Text(cancelling ? '注销中…' : '验证并注销'),
          ),
        ],
      );
}
