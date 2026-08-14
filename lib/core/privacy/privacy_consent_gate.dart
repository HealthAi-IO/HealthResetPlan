import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_theme.dart';
import '../../app/theme_controller.dart';
import '../../features/privacy/privacy_policy_page.dart';

const privacyPolicyUrl = 'https://jkcqplan.com/privacy';
const termsOfServiceUrl = 'https://jkcqplan.com/terms';
const _privacyPolicyVersion = '2026-07-17';
const _privacyConsentKey = 'privacy_policy_version';

class PrivacyConsentGate extends StatefulWidget {
  const PrivacyConsentGate({
    super.key,
    required this.child,
    this.loading,
  });

  final Widget child;
  final Widget? loading;

  @override
  State<PrivacyConsentGate> createState() => _PrivacyConsentGateState();
}

class _PrivacyConsentGateState extends State<PrivacyConsentGate> {
  bool? _accepted;

  @override
  void initState() {
    super.initState();
    _loadConsent();
  }

  Future<void> _loadConsent() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _accepted =
          preferences.getString(_privacyConsentKey) == _privacyPolicyVersion;
    });
  }

  Future<void> _accept() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_privacyConsentKey, _privacyPolicyVersion);
    if (mounted) setState(() => _accepted = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == true) return widget.child;
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '健康重启计划',
        theme: AppTheme.lightFor(themeController.colorTheme.seed),
        darkTheme: AppTheme.darkFor(themeController.colorTheme.seed),
        themeMode: themeController.themeMode,
        home: _accepted == null
            ? Scaffold(
                body: widget.loading ??
                    const Center(child: CircularProgressIndicator()),
              )
            : _PrivacyConsentPage(onAccepted: _accept),
      ),
    );
  }
}

class _PrivacyConsentPage extends StatefulWidget {
  const _PrivacyConsentPage({required this.onAccepted});

  final Future<void> Function() onAccepted;

  @override
  State<_PrivacyConsentPage> createState() => _PrivacyConsentPageState();
}

class _PrivacyConsentPageState extends State<_PrivacyConsentPage> {
  bool _agreed = false;

  Future<void> _openUrl(String value) async {
    await launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
  }

  Future<void> _openPrivacyPolicy() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PrivacyPolicyPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.privacy_tip_outlined,
                      size: 48, color: colors.primary),
                  const SizedBox(height: 18),
                  const Text('隐私保护提示',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text(
                    '健康重启计划将在你同意并登录后处理必要信息，提供在线健康记录、多端同步和提醒服务。敏感健康数据由服务器加密后存储。云端 AI 功能需要在“我的 - AI 数据处理授权”中另行同意。',
                    style:
                        TextStyle(height: 1.55, color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _agreed,
                        onChanged: (value) =>
                            setState(() => _agreed = value ?? false),
                      ),
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('我已阅读并同意'),
                            _ConsentLink(
                              label: '《隐私政策》',
                              onTap: _openPrivacyPolicy,
                            ),
                            const Text('及'),
                            _ConsentLink(
                              label: '《用户协议》',
                              onTap: () => _openUrl(termsOfServiceUrl),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _agreed ? widget.onAccepted : null,
                    child: const Text('同意并继续'),
                  ),
                  TextButton(
                    onPressed: SystemNavigator.pop,
                    child: const Text('不同意并退出'),
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

class _ConsentLink extends StatelessWidget {
  const _ConsentLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
