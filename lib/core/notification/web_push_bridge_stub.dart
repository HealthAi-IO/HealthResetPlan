class WebPushBridge {
  Future<Map<String, dynamic>> subscribe(String publicKey) {
    throw UnsupportedError('Web Push is only available in browsers');
  }

  Future<void> unsubscribe() async {}

  String get permission => 'unsupported';
}
