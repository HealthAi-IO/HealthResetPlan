import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_api.dart';
import '../../core/sync/sync_service.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.initialAccountMode = false,
    this.returnTo = '/home',
  });

  final bool initialAccountMode;
  final String returnTo;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late bool _accountMode = widget.initialAccountMode;
  bool _smsLoginMode = true;
  bool _saving = false;
  bool _sendingCode = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _resendTimer?.cancel();
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
    if (!_smsLoginMode) {
      if (!RegExp(r'^1\d{10}$').hasMatch(phone) || _passwordCtrl.text.isEmpty) {
        setState(() => _error = '请输入手机号和密码');
        return;
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        await _completeAccountAuth(await sl<AuthApi>().loginWithPhonePassword(
          phone: phone,
          password: _passwordCtrl.text,
        ));
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = friendlyAuthError(e));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _error = '请输入正确的手机号');
      return;
    }

    if (code.isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = await sl<AuthApi>().verifyPhone(phone: phone, code: code);
      if (result.status == 'register' && result.registrationTicket != null) {
        if (mounted) {
          context.push('/register',
              extra: RegisterArgs(
                  phone: phone,
                  registrationTicket: result.registrationTicket!,
                  returnTo: widget.returnTo));
        }
      } else if (result.auth != null) {
        await _completeAccountAuth(result.auth!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _completeAccountAuth(AuthResult result) async {
    final existingName = UserSession.instance.name;
    await UserSession.instance.setAccountSession(
      userId: result.userId,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      nickname: existingName.isEmpty ? null : existingName,
      passwordPromptRequired: !result.hasPassword,
    );
    sl<ApiClient>().setAccessToken(result.accessToken);

    final account = await sl<AuthApi>().fetchAccountInfo();
    if (account != null && account.nickname.isNotEmpty) {
      await UserSession.instance.setAccountSession(
        userId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        nickname: account.nickname,
      );
    }
    await sl<KeyVault>().bindToAccount(result.userId);
    await sl<SyncService>().bindToAccount(result.userId);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    context.go(result.hasPassword
        ? widget.returnTo
        : Uri(path: '/set-password', queryParameters: {
            'returnTo': widget.returnTo,
          }).toString());
    unawaited(_syncLocalDataAfterLogin(messenger));
  }

  String _normalizePhone(String raw) =>
      raw.trim().replaceAll(RegExp(r'\D'), '');

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
      _startResendCountdown();
      if (result.debugCode.isNotEmpty) {
        await _showDebugCodeDialog(result.debugCode);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
        return;
      }
      setState(() => _resendSeconds--);
    });
  }

  Future<void> _showDebugCodeDialog(String code) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('验证码'),
        content: Text(
          code,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              _codeCtrl.text = code;
              Navigator.pop(dialogContext);
            },
            child: const Text('自动填入'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncLocalDataAfterLogin(
    ScaffoldMessengerState messenger,
  ) async {
    try {
      final sync = sl<SyncService>();
      final keyState = await sl<KeyVault>().status();
      if (keyState != KeyVaultState.ready) {
        await sync.setSyncEnabled(false);
        messenger.showSnackBar(
          SnackBar(content: Text('登录成功。${keyState.syncMessage}')),
        );
        return;
      }

      await sync.setSyncEnabled(true);

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

  Future<void> _showAccountRecoveryDialog() async {
    final result = await showDialog<_RecoveredAccount>(
      context: context,
      builder: (_) => const _AccountRecoveryDialog(),
    );
    if (result == null || !mounted) return;
    await UserSession.instance.setAccountSession(
      userId: result.auth.userId,
      accessToken: result.auth.accessToken,
      refreshToken: result.auth.refreshToken,
      nickname: result.auth.userId,
      passwordPromptRequired: !result.auth.hasPassword,
    );
    sl<ApiClient>().setAccessToken(result.auth.accessToken);
    await sl<KeyVault>().bindToAccount(result.auth.userId);
    await sl<KeyVault>().restoreFromMnemonic(result.mnemonic);
    await sl<SyncService>().bindToAccount(result.auth.userId);
    if (mounted) context.go('/sync');
  }

  Future<void> _showLoginHelp() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.lock_reset_outlined),
              title: const Text('忘记密码'),
              onTap: () => Navigator.pop(sheetContext, 'reset'),
            ),
            ListTile(
              leading: const Icon(Icons.restore_outlined),
              title: const Text('恢复已注销账号'),
              onTap: () => Navigator.pop(sheetContext, 'recover'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'reset') {
      await _showForgotPasswordDialog();
    } else if (action == 'recover') {
      await _showAccountRecoveryDialog();
    }
  }

  void _toggleAccountMode() {
    setState(() {
      _accountMode = !_accountMode;
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
                    smsLoginMode: _smsLoginMode,
                    saving: _saving,
                    sendingCode: _sendingCode,
                    resendSeconds: _resendSeconds,
                    error: _error,
                    nameCtrl: _nameCtrl,
                    phoneCtrl: _phoneCtrl,
                    codeCtrl: _codeCtrl,
                    passwordCtrl: _passwordCtrl,
                    onSubmit: _submit,
                    onSendCode: _sendLoginCode,
                    onLoginHelp: _showLoginHelp,
                    onLoginModeChanged: (value) =>
                        setState(() => _smsLoginMode = value),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _saving ? null : _toggleAccountMode,
                    child: Text(
                      _accountMode ? '暂不登录，本地使用' : '返回手机号登录',
                    ),
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
    required this.smsLoginMode,
    required this.saving,
    required this.sendingCode,
    required this.resendSeconds,
    required this.error,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.codeCtrl,
    required this.passwordCtrl,
    required this.onSubmit,
    required this.onSendCode,
    required this.onLoginHelp,
    required this.onLoginModeChanged,
  });

  final bool accountMode;
  final bool smsLoginMode;
  final bool saving;
  final bool sendingCode;
  final int resendSeconds;
  final String? error;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController codeCtrl;
  final TextEditingController passwordCtrl;
  final VoidCallback onSubmit;
  final VoidCallback onSendCode;
  final VoidCallback onLoginHelp;
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
              accountMode ? '手机号登录' : '免费版昵称',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          accountMode ? '绑定手机号账号后可使用云同步和在线能力。' : '只保存在本地，无网络也可以使用。',
          style: const TextStyle(color: AppTheme.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (accountMode) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: true,
                  label: Text('验证码登录'),
                  icon: Icon(Icons.sms_outlined)),
              ButtonSegment(
                  value: false,
                  label: Text('密码登录'),
                  icon: Icon(Icons.lock_outline)),
            ],
            selected: {smsLoginMode},
            onSelectionChanged:
                saving ? null : (value) => onLoginModeChanged(value.first),
          ),
          const SizedBox(height: 8),
          if (smsLoginMode)
            const Text(
              '未注册手机号验证后将自动创建账号',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          const SizedBox(height: 12),
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
          if (smsLoginMode) ...[
            TextField(
              controller: codeCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                labelText: '验证码',
                hintText: '请输入 6 位验证码',
                prefixIcon: Icon(Icons.sms_outlined),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: sendingCode || resendSeconds > 0 ? null : onSendCode,
                child: Text(sendingCode
                    ? '发送中...'
                    : resendSeconds > 0
                        ? '重新发送（$resendSeconds 秒）'
                        : '获取验证码'),
              ),
            ),
          ],
          if (resendSeconds > 0) ...[
            const SizedBox(height: 8),
            Text(
                '验证码已发送至 ${phoneCtrl.text.length >= 11 ? '${phoneCtrl.text.substring(0, 3)}****${phoneCtrl.text.substring(phoneCtrl.text.length - 4)}' : '该手机号'}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ],
          if (!smsLoginMode) ...[
            TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    hintText: '登录密码', prefixIcon: Icon(Icons.lock_outline))),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: saving ? null : onLoginHelp,
              child: const Text('登录遇到问题？'),
            ),
          ),
        ],
        if (!accountMode)
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
                    accountMode ? (smsLoginMode ? '验证码登录' : '手机号密码登录') : '开始使用',
                  ),
          ),
        ),
      ]),
    );
  }
}

class _RecoveredAccount {
  const _RecoveredAccount(this.auth, this.phone, this.mnemonic);
  final AuthResult auth;
  final String phone;
  final String mnemonic;
}

class _AccountRecoveryDialog extends StatefulWidget {
  const _AccountRecoveryDialog();
  @override
  State<_AccountRecoveryDialog> createState() => _AccountRecoveryDialogState();
}

class _AccountRecoveryDialogState extends State<_AccountRecoveryDialog> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _mnemonic = TextEditingController();
  bool _sending = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _mnemonic.dispose();
    super.dispose();
  }

  String get _normalizedPhone => _phone.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _sendCode() async {
    if (!RegExp(r'^1\d{10}$').hasMatch(_normalizedPhone)) {
      setState(() => _error = '请输入正确的手机号');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result =
          await sl<AuthApi>().sendAccountRecoveryCode(_normalizedPhone);
      if (result.debugCode.isNotEmpty) {
        _code.text = result.debugCode;
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('验证码'),
              content: Text(
                result.debugCode,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭'),
                ),
                FilledButton(
                  onPressed: () {
                    _code.text = result.debugCode;
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('自动填入'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _recover() async {
    if (!RegExp(r'^1\d{10}$').hasMatch(_normalizedPhone) ||
        _code.text.trim().isEmpty ||
        _mnemonic.text.trim().isEmpty) {
      setState(() => _error = '请填写手机号、验证码和 24 词助记词');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final mnemonic = _mnemonic.text.trim();
      final fingerprint =
          await sl<KeyVault>().fingerprintFromMnemonic(mnemonic);
      final auth = await sl<AuthApi>().reactivateAccount(
          phone: _normalizedPhone,
          code: _code.text.trim(),
          keyFingerprint: fingerprint);
      if (mounted) {
        Navigator.pop(
            context, _RecoveredAccount(auth, _normalizedPhone, mnemonic));
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('恢复已注销账号'),
        content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('仅在注销后 30 天内可恢复。需原手机号验证码和原 24 词助记词；助记词不会上传。',
                  style: TextStyle(fontSize: 13, color: AppTheme.muted)),
              const SizedBox(height: 12),
              TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '原手机号')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '验证码'))),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: _sending ? null : _sendCode,
                    child: Text(_sending ? '发送中...' : '获取验证码'))
              ]),
              const SizedBox(height: 10),
              TextField(
                  controller: _mnemonic,
                  minLines: 3,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '原 24 词助记词')),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!,
                        style: TextStyle(color: Colors.red.shade700))),
            ])),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              onPressed: _saving ? null : _recover,
              child: Text(_saving ? '恢复中...' : '恢复并登录'))
        ],
      );
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

  String _normalizePhone(String raw) =>
      raw.trim().replaceAll(RegExp(r'\D'), '');

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
