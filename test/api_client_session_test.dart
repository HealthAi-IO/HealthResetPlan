import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/auth/user_session.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('concurrent unrecoverable 401 responses expire the session once',
      () async {
    await UserSession.instance.setAccountSession(
      userId: 'account-a',
      accessToken: 'expired-access',
      refreshToken: 'expired-refresh',
    );
    final client = ApiClient(
      baseUrl: 'https://test.invalid/api/v1',
      adapter: _UnauthorizedAdapter(),
    )..setAccessToken('expired-access');
    var expirationCount = 0;
    client.setSessionExpiredHandler(() async {
      expirationCount++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });

    await Future.wait([
      client.dio.get('/one').then<void>((_) {}, onError: (_) {}),
      client.dio.get('/two').then<void>((_) {}, onError: (_) {}),
    ]);

    expect(expirationCount, 1);
    await UserSession.instance.clear(allowLocalMode: true);
  });
}

class _UnauthorizedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"code":40101,"msg":"unauthorized"}',
      401,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
