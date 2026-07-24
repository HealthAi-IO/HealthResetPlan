import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/app/app_theme.dart';
import 'package:health_reset_plan/app/theme_controller.dart';

void main() {
  testWidgets('accent surfaces visibly follow every color theme', (tester) async {
    tester.view.physicalSize = const Size(1200, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const Key('theme-preview'),
          child: Material(
            color: Colors.white,
            child: Row(
              children: [
                for (final item in AppColorTheme.values)
                  Expanded(
                    child: Theme(
                      data: AppTheme.lightFor(item.seed),
                      child: Builder(
                        builder: (context) => Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: AppTheme.accentGradient(context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              item.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const Key('theme-preview')),
      matchesGoldenFile('goldens/theme-accent-surfaces.png'),
    );
  });
}
