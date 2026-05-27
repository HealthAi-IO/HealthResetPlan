import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _ctrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入您的名称');
      return;
    }
    setState(() { _saving = true; _error = null; });
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
      setState(() { _saving = false; _error = '保存失败，请重试'; });
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
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.deepBlue.withValues(alpha: 0.9), const Color(0xFF0288D1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 40),
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
                        const Text(
                          '请输入您的名称',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '仅保存在本地，无需注册账号',
                          style: TextStyle(color: AppTheme.muted, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _ctrl,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: '例如：张三、小明…',
                            prefixIcon: const Icon(Icons.person_outline),
                            errorText: _error,
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
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('开始使用', style: TextStyle(fontSize: 15)),
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
