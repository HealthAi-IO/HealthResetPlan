import '../auth/user_session.dart';
import 'api_client.dart';

class TelemetryApi {
  TelemetryApi({
    required ApiClient client,
    required String platform,
    required String appVersion,
  })  : _client = client,
        _platform = platform,
        _appVersion = appVersion;

  final ApiClient _client;
  final String _platform;
  final String _appVersion;

  Future<void> record(String eventType) async {
    if (!UserSession.instance.isAccountLogin) return;
    try {
      await _client.dio.post('/telemetry/events', data: {
        'platform': _platform,
        'appVersion': _appVersion,
        'eventType': eventType,
      });
    } catch (_) {}
  }
}
