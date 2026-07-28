import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/app/app_theme.dart';
import 'package:health_reset_plan/core/widgets/ai_content_notice.dart';

void main() {
  testWidgets('AI content notice uses the active theme color', (tester) async {
    const seed = Color(0xFFC56518);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightFor(seed),
        home: const Scaffold(
          body: AiContentNotice(feature: '测试'),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.auto_awesome));
    final notice = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AiContentNotice),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = notice.decoration! as BoxDecoration;

    expect(icon.color, seed);
    expect(decoration.color, seed.withValues(alpha: 0.08));
  });
}
