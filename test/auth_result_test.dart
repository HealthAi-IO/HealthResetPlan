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
}
