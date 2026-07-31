import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/app/app_theme.dart';
import 'package:health_reset_plan/features/profile/gender_selector.dart';

void main() {
  setUpAll(_loadAppFont);

  testWidgets('gender uses one field and a bottom selection sheet',
      (tester) async {
    var value = 'female';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => GenderSelector(
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('女'), findsOneWidget);
    expect(find.text('男'), findsNothing);

    await tester.tap(find.text('女'));
    await tester.pumpAndSettle();

    expect(find.text('选择性别'), findsOneWidget);
    expect(find.text('男'), findsOneWidget);
    expect(find.text('暂不填写'), findsOneWidget);

    await tester.tap(find.text('男'));
    await tester.pumpAndSettle();
    expect(value, 'male');
    expect(find.text('选择性别'), findsNothing);
  });

  testWidgets('gender picker mobile layout visual', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const captureKey = ValueKey('gender-picker-capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.fromLTRB(20, 120, 20, 20),
              child: Column(
                children: [
                  GenderSelector(value: 'female', onChanged: _ignoreChange),
                  SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(labelText: '出生年份'),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(labelText: '身高（cm）'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('女'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/gender_selector_bottom_sheet.png'),
    );
  });
}

void _ignoreChange(String _) {}

Future<void> _loadAppFont() async {
  final loader = FontLoader('NotoSansSC')
    ..addFont(
      File('assets/fonts/NotoSansSC-Variable-1.0.12.ttf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  await loader.load();
}
