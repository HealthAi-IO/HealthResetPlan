import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/features/auth/widgets/secure_password_field.dart';

void main() {
  testWidgets('visibility toggle preserves selection and focus loss hides text',
      (tester) async {
    final controller = TextEditingController(text: 'secret123');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SecurePasswordField(controller: controller),
              const TextField(key: Key('other-field')),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(SecurePasswordField));
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();

    expect(
        tester
            .widget<TextField>(find.descendant(
              of: find.byType(SecurePasswordField),
              matching: find.byType(TextField),
            ))
            .obscureText,
        isFalse);
    expect(controller.selection, const TextSelection.collapsed(offset: 4));

    await tester.tap(find.byKey(const Key('other-field')));
    await tester.pump();

    expect(
        tester
            .widget<TextField>(find.descendant(
              of: find.byType(SecurePasswordField),
              matching: find.byType(TextField),
            ))
            .obscureText,
        isTrue);
  });

  testWidgets('backgrounding the app hides visible password', (tester) async {
    final controller = TextEditingController(text: 'secret123');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SecurePasswordField(controller: controller)),
      ),
    );

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump();

    expect(
        tester
            .widget<TextField>(find.descendant(
              of: find.byType(SecurePasswordField),
              matching: find.byType(TextField),
            ))
            .obscureText,
        isTrue);
  });
}
