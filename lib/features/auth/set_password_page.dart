import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/auth_api.dart';
import 'widgets/auth_page_shell.dart';

class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({
    super.key,
    this.returnTo = '/home',
    this.allowSkip = true,
  });

  final String returnTo;
  final bool allowSkip;

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.length < 8 ||
        password.length > 64 ||
        password != _confirmPasswordController.text) {
      setState(() => _error = '请输入两次一致的 8-64 位密码');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await sl<AuthApi>().setInitialPassword(password);
      await UserSession.instance.resolvePasswordPrompt();
      if (mounted) context.go(widget.returnTo);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: widget.allowSkip == false,
        child: AuthPageShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
               Text(
                '设置登录密码',
                style: TextStyle(
                  color: AppTheme.ink,
                  fontSize: 32,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
               Text(
                '设置后，下次可以使用手机号和密码登录。',
                style: TextStyle(color: AppTheme.muted, fontSize: 16),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码（8-64 位）',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认密码',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? '设置中...' : '设置密码并进入'),
              ),
              if (widget.allowSkip) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          await UserSession.instance.resolvePasswordPrompt();
                          if (context.mounted) context.go(widget.returnTo);
                        },
                  child: const Text('暂时不设密码'),
                ),
              ],
              const SizedBox(height: 20),
              const SeniorModeEntry(),
            ],
          ),
        ),
      );
}
