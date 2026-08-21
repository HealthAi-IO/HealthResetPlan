import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';
import 'package:health_reset_plan/features/quit_smoking/quit_smoking_history_pages.dart';
import 'package:health_reset_plan/features/quit_smoking/quit_smoking_models.dart';
import 'package:health_reset_plan/features/quit_smoking/quit_smoking_repository.dart';

void main() {
  testWidgets('戒烟日历在放大字体下不会溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final profile = QuitSmokingProfile(
      mode: QuitSmokingMode.immediate,
      dailyBaseline: 10,
      packCigarettes: 20,
      packPrice: 20,
      smokingYears: 5,
      targetDate: start.millisecondsSinceEpoch,
      motivation: '',
      triggers: const [],
      stageGoal: 0,
      stageStartDate: start.millisecondsSinceEpoch,
      remindersEnabled: false,
      createdAt: start.millisecondsSinceEpoch,
      updatedAt: start.millisecondsSinceEpoch,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.5),
          ),
          child: QuitSmokingCalendarPage(
            profile: profile,
            repository: QuitSmokingRepository(database: AppDatabase.instance),
            events: [
              QuitSmokingEvent(
                type: QuitSmokingEventType.checkIn,
                occurredAt: now.millisecondsSinceEpoch,
                cigarettes: 0,
                intensity: 0,
                success: true,
                trigger: '',
                strategy: '',
                note: '',
                createdAt: now.millisecondsSinceEpoch,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('戒烟日历'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
