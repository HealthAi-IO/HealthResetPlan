import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/app/app_theme.dart';
import 'package:health_reset_plan/features/auth/login_page.dart';

void main() {
  Widget buildLogin({double textScale = 1}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(412, 915)).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: const LoginPage(),
      ),
    );
  }

  testWidgets('登录前必须主动勾选用户协议和隐私政策', (tester) async {
    await tester.pumpWidget(buildLogin());

    expect(find.text('登录即表示已阅读并同意《隐私政策》'), findsNothing);
    expect(find.text('我已阅读并同意'), findsOneWidget);
    expect(find.text('《用户协议》'), findsOneWidget);
    expect(find.text('《隐私政策》'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, '登录 / 注册'));
    await tester.pump();

    expect(find.text('请先阅读并勾选同意用户协议和隐私政策'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(find.text('请先阅读并勾选同意用户协议和隐私政策'), findsNothing);
  });

  testWidgets('协议确认区在大字体下不会溢出', (tester) async {
    await tester.pumpWidget(buildLogin(textScale: 1.6));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('我已阅读并同意'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
  });
}
