import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/auth_api.dart';
import '../auth/widgets/secure_password_field.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  Timer? _timer;
  int _countdown = 0;
  bool _sending = false;
  bool _saving = false;
  String? _error;

  String get _phone => _phoneController.text.replaceAll(RegExp(r'\D'), '');

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!RegExp(r'^1\d{10}$').hasMatch(_phone)) {
      setState(() => _error = '请输入当前账号绑定的 11 位手机号');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await sl<AuthApi>().sendPasswordResetCode(
        credType: 'phone',
        identifier: _phone,
      );
      if (result.debugCode.isNotEmpty) {
        _codeController.text = result.debugCode;
      }
      if (!mounted) return;
      setState(() => _countdown = 60);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _countdown <= 1) {
          timer.cancel();
          if (mounted) setState(() => _countdown = 0);
          return;
        }
        setState(() => _countdown--);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('验证码已发送')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (!RegExp(r'^1\d{10}$').hasMatch(_phone) ||
        _codeController.text.trim().length != 6) {
      setState(() => _error = '请输入绑定手机号和 6 位验证码');
      return;
    }
    if (password.length < 8 ||
        password.length > 64 ||
        password != _confirmPasswordController.text) {
      setState(() => _error = '请输入两次一致的 8-64 位新密码');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await sl<AuthApi>().resetPassword(
        credType: 'phone',
        identifier: _phone,
        code: _codeController.text.trim(),
        newPassword: password,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sending || _saving;
    return AlertDialog(
      title: const Text('修改登录密码'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('验证当前绑定手机号后设置新密码。微信快捷登录不受影响。'),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                enabled: !busy,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: '绑定手机号',
                  prefixIcon: Icon(Icons.phone_android_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '短信验证码',
                  prefixIcon: const Icon(Icons.sms_outlined),
                  suffixIcon: TextButton(
                    onPressed: busy || _countdown > 0 ? null : _sendCode,
                    child: Text(
                      _sending
                          ? '发送中'
                          : _countdown > 0
                              ? '${_countdown}s'
                              : '获取验证码',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SecurePasswordField(
                controller: _passwordController,
                enabled: !busy,
                labelText: '新密码（8-64 位）',
              ),
              const SizedBox(height: 12),
              SecurePasswordField(
                controller: _confirmPasswordController,
                enabled: !busy,
                labelText: '确认新密码',
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: Text(_saving ? '修改中…' : '确认修改'),
        ),
      ],
    );
  }
}
