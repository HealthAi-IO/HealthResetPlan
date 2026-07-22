import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/auth_api.dart';

class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({super.key, this.returnTo = '/home'});

  final String returnTo;

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
        canPop: false,
        child: Scaffold(
          backgroundColor: AppTheme.pageBg,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('设置登录密码'),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '设置密码后，下次可以使用手机号和密码登录。',
                          style: TextStyle(color: AppTheme.muted),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '密码（8-64 位）',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '确认密码',
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _saving ? null : _submit,
                          child: Text(_saving ? '设置中...' : '设置密码并进入'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () async {
                                  await UserSession.instance
                                      .resolvePasswordPrompt();
                                  if (context.mounted) {
                                    context.go(widget.returnTo);
                                  }
                                },
                          child: const Text('暂时不设密码'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
