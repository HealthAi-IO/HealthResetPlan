import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/user_session.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_api.dart';
import '../../core/sync/sync_service.dart';

class RegisterArgs {
  const RegisterArgs({
    required this.phone,
    required this.registrationTicket,
    this.returnTo = '/home',
  });
  final String phone;
  final String registrationTicket;
  final String returnTo;
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, required this.args});
  final RegisterArgs args;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nickname = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _agreed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nickname.text = UserSession.instance.name.trim().isNotEmpty
        ? UserSession.instance.name.trim()
        : _defaultNickname();
  }

  @override
  void dispose() {
    _nickname.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String _defaultNickname() {
    const prefixes = ['健康', '轻盈', '活力', '晴朗'];
    return '${prefixes[Random().nextInt(prefixes.length)]}用户${1000 + Random().nextInt(9000)}';
  }

  Future<void> _submit({required bool skipPassword}) async {
    final nickname = _nickname.text.trim();
    if (nickname.isEmpty || !_agreed) {
      setState(() => _error = '请填写昵称并同意用户协议、隐私政策');
      return;
    }
    if (!skipPassword &&
        (_password.text.length < 8 ||
            _password.text.length > 64 ||
            _password.text != _confirmPassword.text)) {
      setState(() => _error = '请输入两次一致的 8-64 位密码');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await sl<AuthApi>().registerPhone(
        phone: widget.args.phone,
        registrationTicket: widget.args.registrationTicket,
        nickname: nickname,
        password: skipPassword ? null : _password.text,
        agreementVersion: '2026-07-17',
      );
      await UserSession.instance.setAccountSession(
          userId: result.userId,
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
          nickname: nickname,
          passwordPromptRequired: false);
      sl<ApiClient>().setAccessToken(result.accessToken);
      await sl<KeyVault>().bindToAccount(result.userId);
      await sl<SyncService>().bindToAccount(result.userId);
      if (mounted) context.go(widget.args.returnTo);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('注册账号')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text(
              '手机号 ${widget.args.phone.substring(0, 3)}****${widget.args.phone.substring(7)} 已验证'),
          const SizedBox(height: 16),
          TextField(
              controller: _nickname,
              decoration: const InputDecoration(labelText: '昵称')),
          const SizedBox(height: 12),
          TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '设置密码（8-64 位）')),
          const SizedBox(height: 12),
          TextField(
              controller: _confirmPassword,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认密码')),
          CheckboxListTile(
              value: _agreed,
              onChanged: (value) => setState(() => _agreed = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('已阅读并同意用户协议、隐私政策')),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _saving ? null : () => _submit(skipPassword: false),
              child: Text(_saving ? '处理中...' : '设置密码并进入')),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: _saving ? null : () => _submit(skipPassword: true),
              child: const Text('暂时不设密码')),
        ]),
      );
}
