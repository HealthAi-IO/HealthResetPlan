import 'api_client.dart';

class AiConsentApi {
  AiConsentApi({required ApiClient client}) : _client = client;
  final ApiClient _client;

  Future<bool> accepted() async {
    final response = await _client.dio.get('/ai/consent');
    final body = response.data;
    return body is Map && body['code'] == 0 && body['data'] is Map && body['data']['accepted'] == true;
  }

  Future<void> accept() async => _client.dio.post('/ai/consent');
  Future<void> revoke() async => _client.dio.delete('/ai/consent');
}
