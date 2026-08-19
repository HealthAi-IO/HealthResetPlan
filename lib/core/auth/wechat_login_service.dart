import 'dart:async';

import 'package:fluwx/fluwx.dart';

class WechatLoginService {
  WechatLoginService() : _fluwx = Fluwx();
  final Fluwx _fluwx;
  FluwxCancelable? _cancelable;

  Future<void> initialize() async {
    await _fluwx.registerApi(
      appId: 'wx6faad39284b5b1ef',
      doOnAndroid: true,
      doOnIOS: false,
    );
  }

  Future<String?> authorize() async {
    final completer = Completer<String?>();
    final state = DateTime.now().microsecondsSinceEpoch.toString();
    _cancelable?.cancel();
    _cancelable = _fluwx.addSubscriber((response) {
      if (response is! WeChatAuthResponse || completer.isCompleted) return;
      if (response.state != state) return;
      completer.complete(response.isSuccessful ? response.code : null);
    });
    final started = await _fluwx.authBy(
      which: NormalAuth(scope: 'snsapi_userinfo', state: state),
    );
    if (!started) return null;
    return completer.future.timeout(const Duration(minutes: 2), onTimeout: () => null);
  }

  void dispose() => _cancelable?.cancel();
}
