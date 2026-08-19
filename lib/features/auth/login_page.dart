import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/user_session.dart';
import '../../core/auth/wechat_login_service.dart';
import '../../core/data/online_data_service.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_api.dart';
import 'account_recovery_dialog.dart';
import 'register_page.dart';
import 'widgets/captcha_dialog.dart';
import 'widgets/auth_page_shell.dart';
import 'widgets/secure_password_field.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.initialAccountMode = true,
    this.accountOnly = true,
    this.returnTo = '/home',
  });

  final bool initialAccountMode;
  final bool accountOnly;
  final String returnTo;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _smsMode = true;
  bool _submitting = false;
  bool _sendingCode = false;
  int _countdown = 0;
  Timer? _timer;
  String? _phoneError;
  String? _credentialError;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final phone = _normalizedPhone;
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _phoneError = '请输入正确的11位手机号');
      return;
    }
    if (_smsMode && _codeController.text.length != 6) {
      setState(() => _credentialError = '请输入6位验证码');
      return;
    }
    if (!_smsMode && _passwordController.text.isEmpty) {
      setState(() => _credentialError = '请输入密码');
      return;
    }
    setState(() {
      _submitting = true;
      _phoneError = null;
      _credentialError = null;
    });
    try {
      if (_smsMode) {
        final code = _codeController.text;
        final verified = await sl<AuthApi>().verifyPhone(
          phone: phone,
          code: code,
        );
        if (verified.status == 'register' &&
            verified.registrationTicket != null) {
          if (mounted) {
            context.push(
              '/register',
              extra: RegisterArgs(
                phone: phone,
                registrationTicket: verified.registrationTicket!,
                returnTo: widget.returnTo,
              ),
            );
          }
          return;
        }
        if (verified.auth == null) throw StateError('登录结果无效');
        await _completeLogin(verified.auth!);
      } else {
        final ticket = await showLoginCaptchaDialog(
          context: context,
          api: sl<AuthApi>(),
          phone: phone,
        );
        if (ticket == null || ticket.isEmpty) return;
        final result = await sl<AuthApi>().loginWithPhonePassword(
          phone: phone,
          password: _passwordController.text,
          captchaTicket: ticket,
        );
        await _completeLogin(result);
      }
    } catch (error) {
      if (mounted && authErrorCode(error) == 40302) {
        await _openAccountRecovery();
      } else if (mounted) {
        setState(() => _credentialError = friendlyAuthError(error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _loginWithWechat() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final wechat = sl<WechatLoginService>();
      await wechat.initialize();
      final code = await wechat.authorize();
      if (code == null || !mounted) return;
      final result = await sl<AuthApi>().startWechat(code);
      if (result.status == 'login' && result.token != null) {
        await _completeLogin(result.token!);
      } else if (result.status == 'phone_required' && result.ticket != null) {
        final auth = await _showSocialPhoneDialog(result);
        if (auth != null) await _completeLogin(auth);
      } else {
        throw StateError('微信登录结果无效');
      }
    } catch (error) {
      if (mounted) setState(() => _credentialError = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<AuthResult?> _showSocialPhoneDialog(SocialLoginResult social) {
    final phoneController = TextEditingController();
    final codeController = TextEditingController();
    var syncProfile = true;
    var sending = false;
    var countdown = 0;
    Timer? timer;
    return showDialog<AuthResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('绑定手机号后登录'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '手机号')),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '验证码',
                suffixIcon: TextButton(
                  onPressed: sending || countdown > 0 ? null : () async {
                    final phone = phoneController.text.replaceAll(RegExp(r'\D'), '');
                    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) return;
                    setDialogState(() => sending = true);
                    try {
                      final captcha = await showLoginCaptchaDialog(context: context, api: sl<AuthApi>(), phone: phone);
                      if (captcha == null || captcha.isEmpty) return;
                      final sent = await sl<AuthApi>().sendSmsLoginCode(phone: phone, captchaTicket: captcha);
                      if (sent.debugCode.isNotEmpty) codeController.text = sent.debugCode;
                      setDialogState(() => countdown = 60);
                      timer?.cancel();
                      timer = Timer.periodic(const Duration(seconds: 1), (t) {
                        if (!context.mounted || countdown <= 1) { t.cancel(); if (context.mounted) setDialogState(() => countdown = 0); } else { setDialogState(() => countdown--); }
                      });
                    } finally { if (context.mounted) setDialogState(() => sending = false); }
                  },
                  child: Text(countdown > 0 ? '$countdown 秒' : '获取验证码'),
                ),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: syncProfile,
              onChanged: (value) => setDialogState(() => syncProfile = value ?? false),
              title: const Text('同步微信昵称和头像'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ]),
          actions: [
            TextButton(onPressed: () { timer?.cancel(); Navigator.pop(dialogContext); }, child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final phone = phoneController.text.replaceAll(RegExp(r'\D'), '');
                if (!RegExp(r'^1\d{10}$').hasMatch(phone) || codeController.text.length != 6) return;
                final auth = await sl<AuthApi>().verifySocialPhone(ticket: social.ticket!, phone: phone, code: codeController.text, syncProfile: syncProfile);
                if (dialogContext.mounted) { timer?.cancel(); Navigator.pop(dialogContext, auth); }
              },
              child: const Text('确认绑定'),
            ),
          ],
        ),
      ),
    ).whenComplete(() { phoneController.dispose(); codeController.dispose(); timer?.cancel(); });
  }

  Future<void> _completeLogin(AuthResult result) async {
    await UserSession.instance.setAccountSession(
      userId: result.userId,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
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
    if (mounted) context.go(widget.returnTo);
    unawaited(_finishLoginInBackground(result));
  }

  Future<void> _finishLoginInBackground(AuthResult result) async {
    final accountFuture = sl<AuthApi>().fetchAccountInfo();
    try {
      final account = await accountFuture;
      if (account != null && account.nickname.isNotEmpty) {
        await UserSession.instance.setAccountSession(
          userId: result.userId,
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
          nickname: account.nickname,
        );
      }
    } catch (_) {}
  }

  Future<void> _openAccountRecovery() async {
    final result = await showDialog<AuthResult>(
      context: context,
      builder: (context) =>
          AccountRecoveryDialog(initialPhone: _normalizedPhone),
    );
    if (result != null) await _completeLogin(result);
  }

  Future<void> _sendCode() async {
    final phone = _normalizedPhone;
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _phoneError = '请输入正确的11位手机号');
      return;
    }
    final captchaTicket = await showLoginCaptchaDialog(
      context: context,
      api: sl<AuthApi>(),
      phone: phone,
    );
    if (captchaTicket == null || captchaTicket.isEmpty || !mounted) return;
    setState(() {
      _sendingCode = true;
      _phoneError = null;
      _credentialError = null;
    });
    try {
      final result = await sl<AuthApi>().sendSmsLoginCode(
        phone: phone,
        captchaTicket: captchaTicket,
      );
      if (result.debugCode.isNotEmpty) {
        _codeController.text = result.debugCode;
      }
      _timer?.cancel();
      setState(() => _countdown = 60);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _countdown <= 1) {
          timer.cancel();
          if (mounted) setState(() => _countdown = 0);
        } else {
          setState(() => _countdown--);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _phoneError = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  String get _normalizedPhone =>
      _phoneController.text.replaceAll(RegExp(r'\D'), '');

  void _changeLoginMode(bool smsMode) {
    setState(() {
      _smsMode = smsMode;
      _credentialError = null;
    });
  }

  void _submitCompletedCode(String value) {
    if (value.length == 6 && !_submitting) {
      _submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Image.asset(
            'assets/images/health_reset_logo_transparent.png',
            width: 72,
            height: 72,
            alignment: Alignment.centerLeft,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 20),
          Text(
            '欢迎回来',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 10),
          const Text(
            '登录后，继续你的健康重启计划',
            style: TextStyle(color: Color(0xFF65788B), fontSize: 15),
          ),
          const SizedBox(height: 32),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('验证码登录')),
              ButtonSegment(value: false, label: Text('密码登录')),
            ],
            selected: {_smsMode},
            onSelectionChanged:
                _submitting ? null : (value) => _changeLoginMode(value.first),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _phoneController,
            enabled: !_submitting,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textInputAction: TextInputAction.next,
            inputFormatters: const [_ChinesePhoneInputFormatter()],
            onChanged: (_) {
              if (_phoneError != null) setState(() => _phoneError = null);
            },
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: InputDecoration(
              labelText: '手机号',
              prefixIcon: const Icon(Icons.phone_android_rounded),
              prefixText: '+86 ',
              errorText: _phoneError,
            ),
          ),
          const SizedBox(height: 14),
          if (_smsMode)
            TextField(
              controller: _codeController,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (value) {
                if (_credentialError != null) {
                  setState(() => _credentialError = null);
                }
                _submitCompletedCode(value);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '验证码',
                prefixIcon: const Icon(Icons.verified_user_outlined),
                errorText: _credentialError,
                suffixIcon: TextButton(
                  onPressed: _submitting || _sendingCode || _countdown > 0
                      ? null
                      : _sendCode,
                  child: Text(_countdown > 0 ? '$_countdown 秒' : '获取验证码'),
                ),
              ),
            )
          else
            SecurePasswordField(
              controller: _passwordController,
              labelText: '密码',
              enabled: !_submitting,
              errorText: _credentialError,
              onSubmitted: (_) => _submit(),
            ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_smsMode ? '登录 / 注册' : '登录'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.push('/privacy-policy'),
            child: const Text('登录即表示已阅读并同意《隐私政策》'),
          ),
          TextButton(
            onPressed: _submitting ? null : _openAccountRecovery,
            child: const Text('恢复已注销账号'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _loginWithWechat,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('微信登录'),
          ),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('支付宝登录（审核中）'),
          ),
          const SizedBox(height: 20),
          const SeniorModeEntry(),
        ],
      ),
    );
  }
}

class _ChinesePhoneInputFormatter extends TextInputFormatter {
  const _ChinesePhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11 && digits.startsWith('86')) {
      digits = digits.substring(2);
    }
    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
