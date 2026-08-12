import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/auth_api.dart';

class AccountRecoveryDialog extends StatefulWidget {
  const AccountRecoveryDialog({super.key, this.initialPhone = ''});

  final String initialPhone;

  @override
  State<AccountRecoveryDialog> createState() => _AccountRecoveryDialogState();
}

class _AccountRecoveryDialogState extends State<AccountRecoveryDialog> {
  late final TextEditingController _phoneController;
  final _codeController = TextEditingController();
  bool _sending = false;
  bool _recovering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _phone => _phoneController.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _sendCode() async {
    if (!RegExp(r'^1\d{10}$').hasMatch(_phone)) {
      setState(() => _error = '请输入正确的 11 位手机号');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await sl<AuthApi>().sendAccountRecoveryCode(_phone);
      if (result.debugCode.isNotEmpty) {
        _codeController.text = result.debugCode;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('验证码已发送')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _recover() async {
    if (!RegExp(r'^1\d{10}$').hasMatch(_phone) ||
        _codeController.text.trim().length != 6) {
      setState(() => _error = '请输入手机号和 6 位验证码');
      return;
    }
    setState(() {
      _recovering = true;
      _error = null;
    });
    try {
      final result = await sl<AuthApi>().reactivateAccount(
        phone: _phone,
        code: _codeController.text.trim(),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('恢复账号'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('注销后 30 天内，可以通过绑定手机号恢复账号和健康记录。'),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: '绑定手机号'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '短信验证码'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _sending || _recovering ? null : _sendCode,
                  child: Text(_sending ? '发送中…' : '获取验证码'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _recovering ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _recovering ? null : _recover,
          child: Text(_recovering ? '恢复中…' : '恢复账号'),
        ),
      ],
    );
  }
}
