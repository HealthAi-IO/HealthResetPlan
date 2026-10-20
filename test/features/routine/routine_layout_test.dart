import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/features/routine/routine_chart.dart';
import 'package:health_reset_plan/features/routine/routine_poster.dart';

void main() {
  testWidgets('poster and trend fit a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget app(Widget child) => MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 900), textScaler: TextScaler.linear(2)),
            child: child));
    await tester.pumpWidget(app(const RoutinePoster(event: {
      'eventType': 'wake',
      'occurredAt': '2026-10-19T00:00:00Z',
      'quote': '给身体一点晨光，也给今天一点从容。',
      'source': 'live',
      'earlierThan': 12,
      'sampleCount': 20,
      'comparisonDate': '2026-10-18',
    })));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: RoutineChart(
      rows: const [
        {
          'date': '2026-10-19',
          'selfReportedHours': 7.5,
          'wake': {'occurredAt': '2026-10-19T00:00:00Z'},
          'bed': {'occurredAt': '2026-10-18T15:00:00Z'}
        }
      ],
      days: 7,
      endDate: '2026-10-19',
      target: 8,
    )))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
