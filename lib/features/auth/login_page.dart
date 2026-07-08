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

  /// 跳转到登录页时是否直接进入账号登录模式（付费墙引导用）
  final bool initialAccountMode;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _nameCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _loginCodeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late bool _accountMode = widget.initialAccountMode;
  bool _smsLoginMode = true;
  bool _saving = false;
  bool _sendingLoginCode = false;
  String? _debugLoginCode;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _accountCtrl.dispose();
    _loginCodeCtrl.dispose();
    _passwordCtrl.dispose();
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
      setState(() => _error = '请输入您的昵称');
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败，请重试';
      });
    }
  }

  Future<void> _submitAccount() async {
    final identifier = _normalizeIdentifier(_accountCtrl.text);
    final code = _loginCodeCtrl.text.trim();
    final password = _passwordCtrl.text;
    final nickname = _nameCtrl.text.trim();

    if (identifier.isEmpty ||
        (_smsLoginMode ? code.isEmpty : password.isEmpty)) {
      setState(() => _error = _smsLoginMode ? '请输入手机号和验证码' : '请输入手机号和密码');
      return;
    }
    if (!RegExp(r'^1\d{10}$').hasMatch(identifier)) {
      setState(() => _error = '请输入正确的手机号');
      return;
    }
    if (!_smsLoginMode && password.length < 8) {
      setState(() => _error = '密码至少 8 位');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final auth = sl<AuthApi>();
      final result = _smsLoginMode
          ? await auth.smsLogin(
              phone: identifier,
              code: code,
              nickname: nickname.isEmpty ? null : nickname,
            )
          : await auth.login(
              credType: 'phone',
              identifier: identifier,
              password: password,
            );

      await UserSession.instance.setAccountSession(
        userId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        nickname: nickname.isEmpty ? identifier : nickname,
        accountIdentifier: identifier,
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

  String _normalizeIdentifier(String raw) {
    return raw.trim().replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _sendLoginCode() async {
    final phone = _normalizeIdentifier(_accountCtrl.text);
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _error = '请输入正确的手机号');
      return;
    }
    if (_sendingLoginCode) return;
    setState(() {
      _sendingLoginCode = true;
      _error = null;
    });
    try {
      final result = await sl<AuthApi>().sendSmsLoginCode(phone: phone);
      if (!mounted) return;
      setState(() {
        _debugLoginCode = result.debugCode;
        if (result.debugCode.isNotEmpty) {
          _loginCodeCtrl.text = result.debugCode;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _sendingLoginCode = false);
    }
  }

/*
  Future<void> _syncLocalDataAfterLogin(ScaffoldMessengerState messenger) async {
    try {
      final status =
          await sl<MembershipService>().getStatus(forceRefresh: true);
      if (!status.isActive) return;

      final sync = sl<SyncService>();
      await sync.setSyncEnabled(true);

      final umk = await sl<KeyVault>().readUmk();
      if (umk == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('登录成功。云同步需要先恢复主密钥助记词。')),
        );
        return;
      }

      final result = await sync.sync().timeout(
            const Duration(seconds: 8),
            onTimeout: () => const SyncResult(
              pushed: 0,
              pulled: 0,
              error: '云同步仍在后台处理，可稍后手动同步',
            ),
          );
      if (result.hasError) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(_isKeyRestoreRequired(result.error)
                ? '登录成功。云端数据需要恢复主密钥后才能读取。'
                : '登录成功，云同步稍后可重试：${result.error}'),
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
    } catch (_) {
      // 登录流程不因同步失败中断；用户仍可在云同步页手动重试。
      return false;
    }
  }

*/
  Future<void> _syncLocalDataAfterLogin(
      ScaffoldMessengerState messenger) async {
    try {
      final status =
          await sl<MembershipService>().getStatus(forceRefresh: true);
      if (!status.isActive) return;

      final sync = sl<SyncService>();
      await sync.setSyncEnabled(true);

      final umk = await sl<KeyVault>().readUmk();
      if (umk == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('登录成功。云同步前请先恢复主密钥。'),
          ),
        );
        return;
      }

      final result = await sync.sync();
      if (result.hasError) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(_isKeyRestoreRequired(result.error)
                ? '登录成功。请恢复主密钥后读取云端数据。'
                : '登录成功，云同步失败：${result.error}'),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (result.pushed + result.pulled > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '登录成功，云同步完成：${result.pushed + result.pulled} 条',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {
      // Login has already succeeded; background sync must not block the app.
    }
  }

  bool _isKeyRestoreRequired(String? error) {
    final text = error ?? '';
    return text.contains('主密钥') ||
        text.contains('助记词') ||
        text.contains('密钥异常') ||
        text.contains('UMK');
  }

  // ignore: unused_element
  Future<bool?> _showRestoreKeyDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要恢复云端密钥'),
        content: const Text(
          '你当前登录的是同一个账号，但这台设备还没有恢复之前备份的助记词。\n\n云同步数据是端到端加密的，不恢复同一把主密钥就无法读取旧设备上传的数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('现在恢复'),
          ),
        ],
      ),
    );
  }

  Future<void> _showForgotPasswordDialog() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => const _ForgotPasswordDialog(),
    );
    if (updated == true && mounted) {
      setState(() {
        _error = '密码已重置，请使用新密码登录';
      });
    }
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
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _accountMode ? '会员账号登录' : '免费版昵称',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() {
                                        _accountMode = !_accountMode;
                                        _error = null;
                                      }),
                              child: Text(_accountMode ? '使用免费版' : '会员登录'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _accountMode
                              ? '真实账号用于绑定会员权益和 AI 对话。'
                              : '只保存在本地，无网状态也可以使用。',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_accountMode) ...[
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
                            selected: {_smsLoginMode},
                            onSelectionChanged: _saving
                                ? null
                                : (selected) => setState(() {
                                      _smsLoginMode = selected.first;
                                      _error = null;
                                    }),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _accountCtrl,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: '手机号',
                              prefixIcon:
                                  const Icon(Icons.phone_iphone_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_smsLoginMode) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _loginCodeCtrl,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _submit(),
                                    decoration: InputDecoration(
                                      hintText: '验证码',
                                      prefixIcon:
                                          const Icon(Icons.sms_outlined),
                                      errorText: _error,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed:
                                      _sendingLoginCode ? null : _sendLoginCode,
                                  child: Text(
                                    _sendingLoginCode ? '发送中...' : '获取验证码',
                                  ),
                                ),
                              ],
                            ),
                            if (_debugLoginCode != null &&
                                _debugLoginCode!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '开发测试验证码：$_debugLoginCode',
                                style: const TextStyle(
                                  color: AppTheme.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ] else ...[
                            TextField(
                              controller: _passwordCtrl,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                hintText: '密码',
                                prefixIcon: const Icon(Icons.lock_outline),
                                errorText: _error,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed:
                                  _saving ? null : _showForgotPasswordDialog,
                              child: const Text('忘记密码？'),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _nameCtrl,
                          autofocus: !_accountMode,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: _accountMode ? '昵称（可选）' : '例如：张三、小明',
                            prefixIcon: const Icon(Icons.person_outline),
                            errorText: _accountMode ? null : _error,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ? null : _submit,
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _accountMode
                                        ? (_smsLoginMode ? '验证码登录' : '密码登录')
                                        : '开始使用',
                                    style: const TextStyle(fontSize: 15),
                                  ),
                          ),
                        ),
                      ],
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

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _accountCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _sending = false;
  bool _resetting = false;
  String? _debugCode;
  String? _error;

  @override
  void dispose() {
    _accountCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _normalizeIdentifier(String raw) {
    return raw.trim().replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _sendCode() async {
    final identifier = _normalizeIdentifier(_accountCtrl.text);
    if (identifier.isEmpty) {
      setState(() => _error = '请输入手机号');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await sl<AuthApi>().sendPasswordResetCode(
        credType: 'phone',
        identifier: identifier,
      );
      if (!mounted) return;
      setState(() {
        _debugCode = result.debugCode;
        _codeCtrl.text = result.debugCode;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reset() async {
    final identifier = _normalizeIdentifier(_accountCtrl.text);
    final code = _codeCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (identifier.isEmpty || code.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写手机号、验证码和新密码');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = '新密码至少 8 位');
      return;
    }
    setState(() {
      _resetting = true;
      _error = null;
    });
    try {
      await sl<AuthApi>().resetPassword(
        credType: 'phone',
        identifier: identifier,
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
      title: const Text('找回/重置密码'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _accountCtrl,
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
