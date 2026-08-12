import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
