import 'dart:convert';
import 'dart:js_interop';

@JS('hrpPushSubscribe')
external JSPromise<JSString> _subscribe(JSString publicKey);

@JS('hrpPushUnsubscribe')
external JSPromise<JSAny?> _unsubscribe();

@JS('hrpPushPermission')
external JSString _permission();

class WebPushBridge {
  Future<Map<String, dynamic>> subscribe(String publicKey) async {
    final value = (await _subscribe(publicKey.toJS).toDart).toDart;
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> unsubscribe() async {
    await _unsubscribe().toDart;
  }

  String get permission => _permission().toDart;
}
