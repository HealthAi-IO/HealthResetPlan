import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_reset_plan/core/auth/user_session.dart';
import 'package:health_reset_plan/core/network/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await UserSession.instance.setAccountSession(
      userId: 'test-user',
      accessToken: 'expired',
      refreshToken: 'refresh',
    );
  });

  tearDown(() => UserSession.instance.signOut());

  test('expired access token refreshes and retries the protected request',
      () async {
    final adapter = _SessionAdapter(refreshSucceeds: true);
    final client = ApiClient(adapter: adapter)..setAccessToken('expired');

    final response = await client.dio.get<dynamic>('/profile');

    expect(response.statusCode, 200);
    expect(adapter.refreshCount, 1);
    expect(adapter.protectedCount, 2);
    expect(UserSession.instance.accessToken, 'renewed');
    expect(UserSession.instance.isAccountLogin, isTrue);
  });

  test('expired refresh token clears the session and authorization header',
      () async {
    final adapter = _SessionAdapter(refreshSucceeds: false);
    final client = ApiClient(adapter: adapter)..setAccessToken('expired');

    await expectLater(
        client.dio.get<dynamic>('/profile'), throwsA(isA<DioException>()));

    expect(adapter.refreshCount, 1);
    expect(UserSession.instance.isAccountLogin, isFalse);
    expect(UserSession.instance.sessionExpired, isTrue);
    expect(client.dio.options.headers.containsKey('Authorization'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('account_login_required'), isTrue);
  });

  test('login rejection does not refresh or expire an existing session',
      () async {
    final adapter = _SessionAdapter(refreshSucceeds: false);
    final client = ApiClient(adapter: adapter)..setAccessToken('expired');

    await expectLater(
        client.dio.post<dynamic>('/auth/login'), throwsA(isA<DioException>()));

    expect(adapter.refreshCount, 0);
    expect(UserSession.instance.isAccountLogin, isTrue);
  });
}

class _SessionAdapter implements HttpClientAdapter {
  _SessionAdapter({required this.refreshSucceeds});

  final bool refreshSucceeds;
  int refreshCount = 0;
  int protectedCount = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path == '/auth/refresh') {
      refreshCount++;
      if (refreshSucceeds) {
        return _response(200, {
          'code': 0,
          'data': {
            'userId': 'test-user',
            'accessToken': 'renewed',
            'refreshToken': 'next',
          }
        });
      }
    } else if (options.path == '/profile') {
      protectedCount++;
      if (options.headers['Authorization'] == 'Bearer renewed') {
        return _response(200, {
          'code': 0,
          'data': {'ok': true}
        });
      }
    }
    return _response(401, {'code': 40102, 'message': '登录已过期'});
  }

  ResponseBody _response(int status, Map<String, dynamic> body) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });

  @override
  void close({bool force = false}) {}
}
