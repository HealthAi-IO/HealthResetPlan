import 'api_client.dart';

class AiConsentApi {
  AiConsentApi({required ApiClient client}) : _client = client;
  final ApiClient _client;

  Future<bool> accepted() async {
    final response = await _client.dio.get('/ai/consent');
    final data = response.data;
    return data is Map && data['accepted'] == true;
  }

  Future<void> accept() async {
    await _client.dio.post('/ai/consent');
    if (!await accepted()) {
      throw StateError('AI 授权未成功保存，请重试');
    }
  }
  Future<void> revoke() async => _client.dio.delete('/ai/consent');
}
