import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('占位测试：保证测试环境可用', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('健康重启计划'))),
      ),
    );
    expect(find.text('健康重启计划'), findsOneWidget);
  });
}
