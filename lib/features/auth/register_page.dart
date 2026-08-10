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
import 'widgets/auth_page_shell.dart';
import 'widgets/secure_password_field.dart';

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
    final maskedPhone = '${widget.args.phone.substring(0, 3)} **** '
        '${widget.args.phone.substring(7)}';
    return AuthPageShell(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '创建账号',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 10),
          const Text(
            '完成注册，开启你的健康之旅',
            style: TextStyle(color: Color(0xFF65788B), fontSize: 15),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7FE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF36B85A)),
                const SizedBox(width: 12),
                Expanded(child: Text(maskedPhone)),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.maybePop(context),
                  child: const Text('更换手机号'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _nicknameController,
            decoration: const InputDecoration(
              labelText: '昵称',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
          SecurePasswordField(
            controller: _passwordController,
            labelText: '设置密码',
            hintText: '请输入 8—64 位密码',
            enabled: !_saving,
          ),
          const SizedBox(height: 14),
          SecurePasswordField(
            controller: _confirmController,
            labelText: '确认密码',
            hintText: '请再次输入密码',
            enabled: !_saving,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _agreed,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => setState(() => _agreed = value ?? false),
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('我已阅读并同意'),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(termsOfServiceUrl)),
                  child: const Text('《用户协议》'),
                ),
                const Text('和'),
                TextButton(
                  onPressed: () => context.push('/privacy-policy'),
                  child: const Text('《隐私政策》'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('完成注册'),
          ),
          const SizedBox(height: 20),
          const SeniorModeEntry(),
        ],
      ),
    );
  }
}
