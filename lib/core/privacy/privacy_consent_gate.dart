import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_theme.dart';

const privacyPolicyUrl = 'https://jkcqplan.com/privacy';
const termsOfServiceUrl = 'https://jkcqplan.com/terms';
const _privacyPolicyVersion = '2026-07-14';
const _privacyConsentKey = 'privacy_policy_version';

class PrivacyConsentGate extends StatefulWidget {
  const PrivacyConsentGate({super.key, required this.child});

  final Widget child;

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
    if (_accepted == null) {
      return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _PrivacyConsentPage(onAccepted: _accept),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBg,
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
                  const Icon(Icons.privacy_tip_outlined,
                      size: 48, color: AppTheme.deepBlue),
                  const SizedBox(height: 18),
                  const Text('隐私保护提示',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  const Text(
                    '健康重启计划将在你同意后处理必要信息以提供本地健康记录、账号同步和提醒服务。未注册账号时，健康数据仅保存在本机；注册并开启服务后，数据会加密上传用于同步。',
                    style: TextStyle(height: 1.55, color: AppTheme.muted),
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
                            TextButton(
                              onPressed: () => _openUrl(privacyPolicyUrl),
                              child: const Text('《隐私政策》'),
                            ),
                            const Text('和'),
                            TextButton(
                              onPressed: () => _openUrl(termsOfServiceUrl),
                              child: const Text('《用户协议》'),
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
