import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/features/home/home_page.dart';

void main() {
  testWidgets('称重状态卡在窄屏和大字体下完整显示趋势', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 164,
                child: HomeStatusItem(
                  icon: Icons.scale_outlined,
                  label: '称重',
                  done: true,
                  skipped: false,
                  primaryText: '65.0 kg',
                  secondaryText: '较上次下降 0.5 kg',
                  emphasizePrimary: true,
                  onTap: () => tapped = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('65.0 kg'), findsOneWidget);
    expect(find.text('较上次下降 0.5 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final cardBottom = tester.getBottomLeft(find.byType(HomeStatusItem)).dy;
    final trendBottom = tester.getBottomLeft(find.text('较上次下降 0.5 kg')).dy;
    expect(trendBottom, lessThanOrEqualTo(cardBottom));

    await tester.tap(find.byType(HomeStatusItem));
    expect(tapped, isTrue);
  });
}
