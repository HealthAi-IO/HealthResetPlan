import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/membership_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_api.dart';
import '../../core/sync/sync_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.initialAccountMode = false});

  final bool initialAccountMode;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  late bool _accountMode = widget.initialAccountMode;
  bool _smsLoginMode = true;
  bool _registerMode = false;
  bool _saving = false;
  bool _sendingCode = false;
  String? _debugCode;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_accountMode) {
      await _submitAccount();
    } else {
      await _submitLocalName();
    }
  }

  Future<void> _submitLocalName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入昵称');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await UserSession.instance.setName(name);
      final repo = sl<HealthRepository>();
      final existing = await repo.loadProfile();
      await repo.saveProfile(
        (existing ?? UserProfileData.empty()).copyWith(nickname: name),
      );
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
    }
  }

  Future<void> _submitAccount() async {
    final phone = _normalizePhone(_phoneCtrl.text);
    final code = _codeCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;
    final nickname = _nameCtrl.text.trim();

    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _error = '请输入正确的手机号');
      return;
    }

    if (_registerMode) {
      if (password.length < 8) {
        setState(() => _error = '密码至少 8 位');
        return;
      }
      if (password != confirmPassword) {
        setState(() => _error = '两次输入的密码不一致');
        return;
      }
    } else if (_smsLoginMode) {
      if (code.isEmpty) {
        setState(() => _error = '请输入验证码');
        return;
      }
    } else {
      if (password.length < 8) {
        setState(() => _error = '请输入至少 8 位密码');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final auth = sl<AuthApi>();
      final result = _registerMode
          ? await auth.register(
              credType: 'phone',
              identifier: phone,
              password: password,
              nickname: nickname.isEmpty ? null : nickname,
            )
          : _smsLoginMode
              ? await auth.smsLogin(
                  phone: phone,
                  code: code,
                  nickname: nickname.isEmpty ? null : nickname,
                )
              : await auth.login(
                  credType: 'phone',
                  identifier: phone,
                  password: password,
                );

      await UserSession.instance.setAccountSession(
        userId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        nickname: nickname.isEmpty ? phone : nickname,
        accountIdentifier: phone,
      );
      sl<ApiClient>().setAccessToken(result.accessToken);

      if (nickname.isNotEmpty) {
        final repo = sl<HealthRepository>();
        final existing = await repo.loadProfile();
        await repo.saveProfile(
          (existing ?? UserProfileData.empty()).copyWith(nickname: nickname),
        );
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go('/home');
      unawaited(_syncLocalDataAfterLogin(messenger));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyAuthError(e);
      });
    }
  }

  String _normalizePhone(String raw) => raw.trim().replaceAll(RegExp(r'\D'), '');

  Future<void> _sendLoginCode() async {
    final phone = _normalizePhone(_phoneCtrl.text);
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _error = '请输入正确的手机号');
      return;
    }
    if (_sendingCode) return;
    setState(() {
      _sendingCode = true;
      _error = null;
    });
    try {
      final result = await sl<AuthApi>().sendSmsLoginCode(phone: phone);
      if (!mounted) return;
      setState(() {
        _debugCode = result.debugCode;
        if (result.debugCode.isNotEmpty) _codeCtrl.text = result.debugCode;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _syncLocalDataAfterLogin(
    ScaffoldMessengerState messenger,
  ) async {
    try {
      final status = await sl<MembershipService>().getStatus(forceRefresh: true);
      if (!status.isActive) return;

      final sync = sl<SyncService>();
      await sync.setSyncEnabled(true);

      final umk = await sl<KeyVault>().readUmk();
      if (umk == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('登录成功。云同步前请先恢复主密钥。')),
        );
        return;
      }

      final result = await sync.sync();
      if (result.hasError) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('登录成功，云同步失败：${result.error}'),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (result.pushed + result.pulled > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('登录成功，云同步完成：${result.pushed + result.pulled} 条'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _showForgotPasswordDialog() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => const _ForgotPasswordDialog(),
    );
    if (updated == true && mounted) {
      setState(() => _error = '密码已重置，请使用新密码登录');
    }
  }

  void _toggleAccountMode() {
    setState(() {
      _accountMode = !_accountMode;
      _registerMode = false;
      _error = null;
    });
  }

  void _toggleRegisterMode() {
    setState(() {
      _registerMode = !_registerMode;
      if (_registerMode) _smsLoginMode = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.deepBlue.withValues(alpha: 0.9),
                          const Color(0xFF0288D1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '健康重启计划',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '本地优先 · 隐私安全 · 智能规划',
                    style: TextStyle(color: AppTheme.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 40),
                  _LoginCard(
                    accountMode: _accountMode,
                    registerMode: _registerMode,
                    smsLoginMode: _smsLoginMode,
                    saving: _saving,
                    sendingCode: _sendingCode,
                    error: _error,
                    debugCode: _debugCode,
                    nameCtrl: _nameCtrl,
                    phoneCtrl: _phoneCtrl,
                    codeCtrl: _codeCtrl,
                    passwordCtrl: _passwordCtrl,
                    confirmPasswordCtrl: _confirmPasswordCtrl,
                    onSubmit: _submit,
                    onSendCode: _sendLoginCode,
                    onForgotPassword: _showForgotPasswordDialog,
                    onToggleAccountMode: _toggleAccountMode,
                    onToggleRegisterMode: _toggleRegisterMode,
                    onLoginModeChanged: (value) => setState(() {
                      _smsLoginMode = value;
                      _registerMode = false;
                      _error = null;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.accountMode,
    required this.registerMode,
    required this.smsLoginMode,
    required this.saving,
    required this.sendingCode,
    required this.error,
    required this.debugCode,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.codeCtrl,
    required this.passwordCtrl,
    required this.confirmPasswordCtrl,
    required this.onSubmit,
    required this.onSendCode,
    required this.onForgotPassword,
    required this.onToggleAccountMode,
    required this.onToggleRegisterMode,
    required this.onLoginModeChanged,
  });

  final bool accountMode;
  final bool registerMode;
  final bool smsLoginMode;
  final bool saving;
  final bool sendingCode;
  final String? error;
  final String? debugCode;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController codeCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmPasswordCtrl;
  final VoidCallback onSubmit;
  final VoidCallback onSendCode;
  final VoidCallback onForgotPassword;
  final VoidCallback onToggleAccountMode;
  final VoidCallback onToggleRegisterMode;
  final ValueChanged<bool> onLoginModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              accountMode ? (registerMode ? '注册账号' : '会员账号登录') : '免费版昵称',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          TextButton(
            onPressed: saving ? null : onToggleAccountMode,
            child: Text(accountMode ? '使用免费版' : '会员登录'),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          accountMode
              ? '账号用于会员权益、AI 功能和云同步。'
              : '只保存在本地，无网络也可以使用。',
          style: const TextStyle(color: AppTheme.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (accountMode) ...[
          if (!registerMode)
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('验证码登录'),
                  icon: Icon(Icons.sms_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('密码登录'),
                  icon: Icon(Icons.lock_outline),
                ),
              ],
              selected: {smsLoginMode},
              onSelectionChanged:
                  saving ? null : (selected) => onLoginModeChanged(selected.first),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: saving ? null : onToggleRegisterMode,
              child: Text(registerMode ? '已有账号，去登录' : '没有账号，立即注册'),
            ),
          ),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: '手机号',
              prefixIcon: Icon(Icons.phone_iphone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          if (!registerMode && smsLoginMode)
            Row(children: [
              Expanded(
                child: TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSubmit(),
                  decoration: const InputDecoration(
                    hintText: '验证码',
                    prefixIcon: Icon(Icons.sms_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: sendingCode ? null : onSendCode,
                child: Text(sendingCode ? '发送中...' : '获取验证码'),
              ),
            ])
          else ...[
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              textInputAction:
                  registerMode ? TextInputAction.next : TextInputAction.done,
              onSubmitted: (_) => registerMode ? null : onSubmit(),
              decoration: const InputDecoration(
                hintText: '密码',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            if (registerMode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordCtrl,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  hintText: '确认密码',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],
          ],
          if (debugCode != null && debugCode!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '开发测试验证码：$debugCode',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
          if (!registerMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: saving ? null : onForgotPassword,
                child: const Text('忘记密码？'),
              ),
            ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: nameCtrl,
          autofocus: !accountMode,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            hintText: accountMode ? '昵称（可选）' : '例如：张三、小明',
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: TextStyle(color: Colors.red.shade700)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: saving ? null : onSubmit,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    accountMode
                        ? (registerMode
                            ? '注册并登录'
                            : (smsLoginMode ? '验证码登录' : '密码登录'))
                        : '开始使用',
                  ),
          ),
        ),
      ]),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _sending = false;
  bool _resetting = false;
  String? _debugCode;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _normalizePhone(String raw) => raw.trim().replaceAll(RegExp(r'\D'), '');

  Future<void> _sendCode() async {
    final phone = _normalizePhone(_phoneCtrl.text);
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _error = '请输入正确的手机号');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await sl<AuthApi>().sendPasswordResetCode(
        credType: 'phone',
        identifier: phone,
      );
      if (!mounted) return;
      setState(() {
        _debugCode = result.debugCode;
        if (result.debugCode.isNotEmpty) _codeCtrl.text = result.debugCode;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reset() async {
    final phone = _normalizePhone(_phoneCtrl.text);
    final code = _codeCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (!RegExp(r'^1\d{10}$').hasMatch(phone) ||
        code.isEmpty ||
        password.length < 8) {
      setState(() => _error = '请填写手机号、验证码和至少 8 位新密码');
      return;
    }

    setState(() {
      _resetting = true;
      _error = null;
    });
    try {
      await sl<AuthApi>().resetPassword(
        credType: 'phone',
        identifier: phone,
        code: code,
        newPassword: password,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重置密码'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: '手机号',
              prefixIcon: Icon(Icons.phone_iphone_outlined),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '验证码',
                  prefixIcon: Icon(Icons.sms_outlined),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _sending ? null : _sendCode,
              child: Text(_sending ? '发送中...' : '获取验证码'),
            ),
          ]),
          if (_debugCode != null && _debugCode!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '开发测试验证码：$_debugCode',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '新密码（至少 8 位）',
              prefixIcon: Icon(Icons.lock_reset_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: _resetting ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _resetting ? null : _reset,
          child: Text(_resetting ? '重置中...' : '重置密码'),
        ),
      ],
    );
  }
}
