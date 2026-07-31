import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_messenger.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/online_data_service.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_api.dart';
import 'account_recovery_dialog.dart';
import 'register_page.dart';
import 'widgets/captcha_dialog.dart';
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

  Future<void> _completeLogin(AuthResult result) async {
    await UserSession.instance.setAccountSession(
      userId: result.userId,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      passwordPromptRequired: false,
    );
    sl<ApiClient>().setAccessToken(result.accessToken);
    await sl<OnlineDataService>().activateAccount(result.userId);
    if (mounted) context.go(widget.returnTo);
    unawaited(_finishLoginInBackground(result));
  }

  Future<void> _finishLoginInBackground(AuthResult result) async {
    final accountFuture = sl<AuthApi>().fetchAccountInfo();
    try {
      await sl<OnlineDataService>().syncAccount();
    } catch (_) {
      _showSyncFailure();
    }
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

  void _showSyncFailure() {
    appMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text('云端数据同步失败，本次登录仍可使用'),
        action: SnackBarAction(
          label: '重试',
          onPressed: () async {
            try {
              await sl<OnlineDataService>().syncAccount();
            } catch (_) {
              _showSyncFailure();
            }
          },
        ),
      ),
    );
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
    return Scaffold(
      appBar: AppBar(title: const Text('登录健康重启计划')),
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
                      '现在出发，重新找回健康的自己！',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '从一次真实记录、一次认真行动开始，让身体一点一点回到更好的状态。',
                      style: TextStyle(color: Colors.black54, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('验证码登录')),
                        ButtonSegment(value: false, label: Text('密码登录')),
                      ],
                      selected: {_smsMode},
                      onSelectionChanged: _submitting
                          ? null
                          : (value) => _changeLoginMode(value.first),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _phoneController,
                      enabled: !_submitting,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      textInputAction: TextInputAction.next,
                      inputFormatters: const [_ChinesePhoneInputFormatter()],
                      onChanged: (_) {
                        if (_phoneError != null) {
                          setState(() => _phoneError = null);
                        }
                      },
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      decoration: InputDecoration(
                        labelText: '手机号',
                        prefixText: '+86 ',
                        errorText: _phoneError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_smsMode)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
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
                                errorText: _credentialError,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed:
                                _submitting || _sendingCode || _countdown > 0
                                ? null
                                : _sendCode,
                            child: Text(
                              _countdown > 0 ? '$_countdown 秒' : '获取验证码',
                            ),
                          ),
                        ],
                      )
                    else
                      SecurePasswordField(
                        controller: _passwordController,
                        labelText: '密码',
                        enabled: !_submitting,
                        errorText: _credentialError,
                        onSubmitted: (_) => _submit(),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('登录 / 注册'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _submitting ? null : _openAccountRecovery,
                      child: const Text('恢复已注销账号'),
                    ),
                    TextButton(
                      onPressed: () => context.push('/privacy-policy'),
                      child: const Text('查看《隐私政策》'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
