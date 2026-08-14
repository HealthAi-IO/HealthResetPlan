import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';

ClockRecordData record({
  required String type,
  required String note,
  num? value,
  String unit = '',
  String detail = '',
}) =>
    ClockRecordData(
      type: type,
      status: 'done',
      clockAt: 0,
      note: note,
      photoPath: '',
      value: value,
      unit: unit,
      detail: detail,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  test('饮水优先读取结构化数值并兼容旧备注', () {
    expect(
      record(type: 'water', note: '饮水 200 ml', value: 300, unit: 'ml')
          .waterMilliliters,
      300,
    );
    expect(
      record(type: 'water', note: '饮水 500 ml').waterMilliliters,
      500,
    );
  });

  test('运动优先读取结构化时长和类型并兼容旧备注', () {
    final structured = record(
      type: 'exercise',
      note: '快走 30 分钟',
      value: 45,
      unit: 'minute',
      detail: '瑜伽',
    );
    expect(structured.exerciseMinutes, 45);
    expect(structured.exerciseName, '瑜伽');
    expect(structured.displayDetail, '瑜伽 45 分钟');

    final legacy = record(type: 'exercise', note: '骑行 20 分钟');
    expect(legacy.exerciseMinutes, 20);
    expect(legacy.exerciseName, '骑行');
  });

  test('体重和饮食记录兼容结构化数值与旧备注', () {
    expect(
      record(type: 'weight', note: '体重 67.8 kg').weightKilograms,
      67.8,
    );
    final meal = record(type: 'meal', note: '午餐 家常菜 560 kcal');
    expect(meal.mealName, '午餐');
    expect(meal.mealCalories, 560);
    expect(meal.displayDetail, '午餐 · 560 kcal');
  });
}
