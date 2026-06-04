import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_api.dart';

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
  final _passwordCtrl = TextEditingController();

  late bool _accountMode = widget.initialAccountMode;
  bool _registerMode = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _accountCtrl.dispose();
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
    final identifier = _accountCtrl.text.trim();
    final password = _passwordCtrl.text;
    final nickname = _nameCtrl.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入账号和密码');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = '密码至少 8 位');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final credType = identifier.contains('@') ? 'email' : 'phone';
      final auth = sl<AuthApi>();
      final result = _registerMode
          ? await auth.register(
              credType: credType,
              identifier: identifier,
              password: password,
              nickname: nickname.isEmpty ? null : nickname,
            )
          : await auth.login(
              credType: credType,
              identifier: identifier,
              password: password,
            );

      await UserSession.instance.setAccountSession(
        userId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        nickname: nickname.isEmpty ? null : nickname,
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
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyAuthError(e);
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
                          TextField(
                            controller: _accountCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: '手机号或邮箱',
                              prefixIcon: const Icon(Icons.alternate_email),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordCtrl,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: '密码（至少 8 位）',
                              prefixIcon: const Icon(Icons.lock_outline),
                              errorText: _error,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                        if (_accountMode) ...[
                          const SizedBox(height: 10),
                          CheckboxListTile(
                            value: _registerMode,
                            onChanged: _saving
                                ? null
                                : (value) => setState(
                                      () => _registerMode = value ?? false,
                                    ),
                            title: const Text('还没有账号，直接注册'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
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
                                        ? (_registerMode ? '注册并登录' : '登录')
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
