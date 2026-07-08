import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fluwx/fluwx.dart';

class WechatPayService {
  WechatPayService({Fluwx? fluwx}) : _fluwx = fluwx ?? Fluwx();

  static const _appId = 'wx6faad39284b5b1ef';

  final Fluwx _fluwx;
  bool _registered = false;

  Future<void> pay(Map<String, dynamic> credential) async {
    await _ensureReady();

    final completer = Completer<void>();
    late WeChatResponseSubscriber listener;
    listener = (response) {
      if (response is! WeChatPaymentResponse || completer.isCompleted) return;
      _fluwx.removeSubscriber(listener);
      if (response.isSuccessful) {
        completer.complete();
      } else if (response.errCode == -2) {
        completer.completeError(StateError('Payment cancelled'));
      } else {
        completer.completeError(
          StateError(response.errStr?.isNotEmpty == true
              ? response.errStr!
              : 'Wechat payment failed'),
        );
      }
    };

    _fluwx.addSubscriber(listener);
    try {
      final sent = await _fluwx.pay(
        which: Payment(
          appId: credential['appid']?.toString() ?? '',
          partnerId: credential['partnerId']?.toString() ?? '',
          prepayId: credential['prepayId']?.toString() ?? '',
          packageValue: credential['package']?.toString() ?? '',
          nonceStr: credential['nonceStr']?.toString() ?? '',
          timestamp:
              int.tryParse(credential['timeStamp']?.toString() ?? '') ?? 0,
          sign: credential['sign']?.toString() ?? '',
        ),
      );
      if (!sent) throw StateError('Cannot open WeChat payment');
      await completer.future.timeout(const Duration(minutes: 5));
    } finally {
      _fluwx.removeSubscriber(listener);
    }
  }

  Future<void> _ensureReady() async {
    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!supported) {
      throw StateError('WeChat payment only supports Android and iOS');
    }

    if (!_registered) {
      final ok = await _fluwx.registerApi(appId: _appId);
      if (!ok) throw StateError('WeChat SDK init failed');
      _registered = true;
    }

    final installed = await _fluwx.isWeChatInstalled;
    if (!installed) throw StateError('Please install WeChat first');
  }
}
