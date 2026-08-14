import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/widgets/numeric_picker_field.dart';

void main() {
  testWidgets('数值选择器不提供可编辑输入框并可确认默认值', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NumericPickerField(
            controller: controller,
            label: '体重',
            unit: 'kg',
            min: 20,
            max: 300,
            step: 0.1,
            decimals: 1,
            initialValue: 65,
          ),
        ),
      ),
    );

    expect(find.byType(EditableText), findsNothing);
    expect(tester.widget<InputDecorator>(find.byType(InputDecorator)).isEmpty,
        isFalse);
    await tester.tap(find.text('请选择'));
    await tester.pumpAndSettle();

    expect(find.text('体重'), findsWidgets);
    expect(find.byType(ListWheelScrollView), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(controller.text, '65.0');
    expect(find.text('65.0 kg'), findsOneWidget);
  });

  testWidgets('可选数值可以清空', (tester) async {
    final controller = TextEditingController(text: '30');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NumericPickerField(
            controller: controller,
            label: '运动时长',
            unit: '分钟',
            min: 5,
            max: 600,
            step: 5,
            optional: true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('30 分钟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(controller.text, isEmpty);
    expect(find.text('未设置'), findsOneWidget);
  });

  testWidgets('平板上的数值选择器保持合适宽度', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NumericPickerField(
            controller: controller,
            label: '体重',
            min: 20,
            max: 300,
            step: 0.1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('请选择'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('numeric-picker-sheet'))).width,
      lessThanOrEqualTo(520),
    );
  });
}
