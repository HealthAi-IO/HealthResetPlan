import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/widgets/health_ui.dart';

void main() {
  testWidgets('平板内容居中并限制阅读宽度', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HealthResponsiveContent(
            maxWidth: 900,
            child: ColoredBox(
              key: ValueKey('content'),
              color: Colors.blue,
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byKey(const ValueKey('content')));
    expect(rect.width, 900);
    expect(rect.left, 250);
  });
}
