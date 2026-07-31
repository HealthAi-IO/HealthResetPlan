import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/user_session.dart';
import '../../core/data/online_data_service.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_api.dart';
import '../../core/privacy/privacy_consent_gate.dart';

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
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _agreed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nicknameController.text = '健康用户${1000 + Random().nextInt(9000)}';
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nickname = _nicknameController.text.trim();
    final password = _passwordController.text;
    if (nickname.isEmpty) {
      setState(() => _error = '请输入昵称');
      return;
    }
    if (password.length < 8 ||
        password.length > 64 ||
        password != _confirmController.text) {
      setState(() => _error = '请输入两次一致的 8—64 位密码');
      return;
    }
    if (!_agreed) {
      setState(() => _error = '请先同意用户协议和隐私政策');
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
        password: password,
        agreementVersion: '2026-07-28',
      );
      await UserSession.instance.setAccountSession(
        userId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        nickname: nickname,
        passwordPromptRequired: false,
      );
      sl<ApiClient>().setAccessToken(result.accessToken);
      try {
        await sl<OnlineDataService>().bindToAccount(result.userId);
      } catch (_) {
        await UserSession.instance.signOut();
        sl<ApiClient>().setAccessToken(null);
        rethrow;
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        UserSession.welcomeLetterPendingUserKey,
        result.userId,
      );
      if (mounted) context.go(widget.args.returnTo);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册账号')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '手机号 ${widget.args.phone.substring(0, 3)}****'
            '${widget.args.phone.substring(7)} 已验证',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nicknameController,
            decoration: const InputDecoration(labelText: '昵称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '设置密码'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '确认密码'),
          ),
          CheckboxListTile(
            value: _agreed,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => setState(() => _agreed = value ?? false),
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('我已阅读并同意'),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(termsOfServiceUrl)),
                  child: const Text('用户协议'),
                ),
                const Text('和'),
                TextButton(
                  onPressed: () => context.push('/privacy-policy'),
                  child: const Text('隐私政策'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('完成注册'),
          ),
        ],
      ),
    );
  }
}
