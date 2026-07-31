import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/app/app_theme.dart';
import 'package:health_reset_plan/features/auth/onboarding_page.dart';
import 'package:health_reset_plan/features/shell/app_shell.dart';

void main() {
  testWidgets('more menu contains the main app shortcuts', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const AppShell(
          location: '/home',
          child: SizedBox.shrink(),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.text('AI 健康顾问'), findsOneWidget);
    expect(find.text('健康档案'), findsOneWidget);
    expect(find.text('录入健康指标'), findsOneWidget);
    expect(find.text('报告识别'), findsOneWidget);
    expect(find.text('AI 数据处理授权'), findsOneWidget);
    expect(find.text('外观主题'), findsOneWidget);
    expect(find.text('使用引导'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
  });

  testWidgets('onboarding accents follow the active color theme',
      (tester) async {
    const seed = Color(0xFF6D55C5);
    final theme = AppTheme.lightFor(seed);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const OnboardingPage(),
      ),
    );

    final icon = tester.widget<Icon>(
      find.byIcon(Icons.assignment_ind_outlined),
    );
    expect(icon.color, theme.colorScheme.onPrimaryContainer);
    expect(find.text('多彩主题'), findsOneWidget);
    await tester.fling(
      find.byType(ListView),
      const Offset(0, -700),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('使用 AI 健康工具'), findsOneWidget);
  });
}
