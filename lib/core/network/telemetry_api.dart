import '../auth/user_session.dart';
import 'api_client.dart';

class TelemetryApi {
  TelemetryApi({required ApiClient client, required String platform})
      : _client = client,
        _platform = platform;

  final ApiClient _client;
  final String _platform;

  Future<void> record(String eventType) async {
    if (!UserSession.instance.isAccountLogin) return;
    try {
      await _client.dio.post('/telemetry/events', data: {
        'platform': _platform,
        'appVersion': '0.1.0',
        'eventType': eventType,
      });
    } catch (_) {}
  }
}
