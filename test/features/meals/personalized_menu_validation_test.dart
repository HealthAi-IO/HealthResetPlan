import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/features/meals/personalized_menu_page.dart';

void main() {
  test('菜单必须先选择目标', () {
    expect(
      personalizedMenuValidationError(
        goal: null,
        goalDetail: '',
        allergies: const [],
        noKnownAllergies: true,
      ),
      '请先选择本次菜单想达成的目标',
    );
  });

  test('其他目标必须填写具体内容', () {
    expect(
      personalizedMenuValidationError(
        goal: 'custom',
        goalDetail: '',
        allergies: const [],
        noKnownAllergies: true,
      ),
      '选择“其他目标”后，请填写具体目标',
    );
  });

  test('过敏食物必须填写或明确确认没有过敏', () {
    expect(
      personalizedMenuValidationError(
        goal: 'maintain',
        goalDetail: '',
        allergies: const [],
        noKnownAllergies: false,
      ),
      '请填写过敏食物，或确认没有已知食物过敏',
    );
    expect(
      personalizedMenuValidationError(
        goal: 'maintain',
        goalDetail: '',
        allergies: const [],
        noKnownAllergies: true,
      ),
      isNull,
    );
  });
}
