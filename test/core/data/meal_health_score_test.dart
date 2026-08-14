import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';

void main() {
  test('AI 百分制餐食评分转换为十分制', () {
    expect(mealHealthScoreFromAi(82), 8.2);
    expect(mealHealthScoreFromAi(-1), 0);
    expect(mealHealthScoreFromAi(120), 10);
  });

  test('历史餐食评分兼容十分制和百分制', () {
    expect(mealHealthScoreOutOfTen(8.5), 8.5);
    expect(mealHealthScoreOutOfTen(80), 8);
  });
}
