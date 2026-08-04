import 'package:flutter/foundation.dart';

import '../network/web_push_api.dart';
import 'web_push_bridge.dart';

class WebPushService {
  WebPushService({required WebPushApi api}) : _api = api;

  final WebPushApi _api;
  final WebPushBridge _bridge = WebPushBridge();

  Future<bool> enable() async {
    if (!kIsWeb) return true;
    final config = await _api.loadConfig();
    if (!config.enabled || config.publicKey.isEmpty) return false;
    try {
      final subscription = await _bridge.subscribe(config.publicKey);
      await _api.subscribe(subscription);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool?> isEnabled() async {
    if (!kIsWeb) return null;
    return _bridge.permission == 'granted';
  }

  Future<void> disable({bool notifyServer = true}) async {
    if (!kIsWeb) return;
    await _bridge.unsubscribe();
    if (notifyServer) await _api.unsubscribe();
  }
}
