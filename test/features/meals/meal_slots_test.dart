import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';
import 'package:health_reset_plan/features/meals/meal_slots.dart';

void main() {
  testWidgets('三餐记录入口传递用户选中的餐次', (tester) async {
    String? selectedMealType;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealSlots(
            meals: const [],
            onAdd: (mealType) => selectedMealType = mealType,
            onEdit: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, '记录').first);
    expect(selectedMealType, 'breakfast');

    await tester.tap(find.widgetWithText(TextButton, '记录').at(1));
    expect(selectedMealType, 'lunch');

    await tester.tap(find.widgetWithText(TextButton, '记录').last);
    expect(selectedMealType, 'dinner');
  });

  testWidgets('同一餐次的多条记录全部显示并可分别打开', (tester) async {
    final opened = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    MealRecordData meal(String clientId, String name) => MealRecordData(
          clientId: clientId,
          name: name,
          mealType: 'lunch',
          eatenAt: now,
          imagePath: '',
          totalCalories: 300,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          healthScore: 8,
          glycemicLoad: 0,
          foods: const [],
          nutrition: const {},
          createdAt: now,
          updatedAt: now,
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealSlots(
            meals: [meal('meal-1', '午餐一'), meal('meal-2', '午餐二')],
            onAdd: (_) {},
            onEdit: (value) => opened.add(value.name),
          ),
        ),
      ),
    );

    expect(find.text('午餐一'), findsOneWidget);
    expect(find.text('午餐二'), findsOneWidget);
    expect(find.text('已记录 2 次'), findsOneWidget);

    await tester.tap(find.text('午餐一'));
    await tester.tap(find.text('午餐二'));
    expect(opened, ['午餐一', '午餐二']);
  });
}
