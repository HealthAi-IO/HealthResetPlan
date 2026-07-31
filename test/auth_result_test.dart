import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/network/auth_api.dart';

void main() {
  test('auth result reads password state', () {
    final result = AuthResult.fromJson({
      'userId': '100000000001',
      'accessToken': 'access',
      'refreshToken': 'refresh',
      'accessExpiresIn': 900,
      'hasPassword': true,
    });

    expect(result.hasPassword, isTrue);
  });

  test('missing password state defaults to false', () {
    final result = AuthResult.fromJson({
      'userId': '100000000001',
      'accessToken': 'access',
      'refreshToken': 'refresh',
      'accessExpiresIn': 900,
    });

    expect(result.hasPassword, isFalse);
  });

  test('account recovery errors preserve their business code', () {
    const error = AuthApiException(40302, '账号处于恢复期');

    expect(authErrorCode(error), 40302);
    expect(friendlyAuthError(error), '账号处于恢复期');
  });
}
