import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';
import 'package:health_reset_plan/core/widgets/medication_reminder_dialog.dart';

void main() {
  testWidgets('用药提醒在窄屏大字体下可以正常显示和关闭', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final scheduledAt = DateTime(2026, 9, 29, 7);
    final reminder = ReminderData(
      id: 1,
      type: 'medicine',
      remindAt: scheduledAt.millisecondsSinceEpoch,
      payload: const {
        'medicineName': '瑞舒伐他汀',
        'dose': '1片',
        'instructions': '温水送服',
        'dailyTimes': [
          {'hour': 7, 'minute': 0},
        ],
      },
      channel: 'local',
      status: 'pending',
      createdAt: 0,
      updatedAt: 0,
    );
    var taken = false;
    var finished = false;
    final saveCompleted = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showMedicationReminderDialog(
                      context,
                      reminder: reminder,
                      scheduledAt: scheduledAt,
                      seniorMode: true,
                      onTaken: () async {
                        taken = true;
                        await saveCompleted.future;
                      },
                      onSnooze: () async {},
                      onSkipped: () async {},
                    ).then((_) => finished = true);
                  },
                  child: const Text('显示提醒'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示提醒'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('您该吃药了'), findsOneWidget);
    expect(find.text('瑞舒伐他汀'), findsOneWidget);
    expect(find.text('1片 · 温水送服'), findsOneWidget);

    await tester.tap(find.text('确认已服'));
    await tester.pumpAndSettle();

    expect(taken, isTrue);
    expect(finished, isFalse);
    expect(find.text('您该吃药了'), findsNothing);
    expect(tester.takeException(), isNull);
    saveCompleted.complete();
    await tester.pump();
    expect(finished, isTrue);
  });
}
