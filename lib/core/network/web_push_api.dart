import 'api_client.dart';

class WebPushConfig {
  const WebPushConfig({required this.enabled, required this.publicKey});
  final bool enabled;
  final String publicKey;
}

class WebPushApi {
  WebPushApi({required ApiClient client}) : _client = client;
  final ApiClient _client;

  Future<WebPushConfig> loadConfig() async {
    final response = await _client.dio.get('/push/config');
    final body = response.data;
    final data = body is Map && body['data'] is Map ? body['data'] as Map : const {};
    return WebPushConfig(
      enabled: data['enabled'] == true,
      publicKey: data['publicKey'] as String? ?? '',
    );
  }

  Future<void> subscribe(Map<String, dynamic> subscription) async {
    await _client.dio.put('/push/subscription', data: subscription);
  }

  Future<void> unsubscribe() async {
    await _client.dio.delete('/push/subscription');
  }
}
