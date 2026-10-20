import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';
import 'package:health_reset_plan/features/routine/routine_summary.dart';
import 'package:health_reset_plan/features/routine/routine_service.dart';

void main() {
  HealthIndicatorEntry sleep(double hours, String updated) =>
      HealthIndicatorEntry(
          type: 'sleep',
          payload: {'sleepHours': hours},
          source: 'manual',
          measuredAt:
              DateTime.parse('2026-10-18T23:00:00Z').millisecondsSinceEpoch,
          createdAt: 0,
          updatedAt: DateTime.parse(updated).millisecondsSinceEpoch);

  test('Beijing midnight assigns the next natural day', () {
    expect(routineDate(DateTime.parse('2026-10-18T16:00:00Z')), '2026-10-19');
  });
  test('newest confirmation wins without counting estimates twice', () {
    final sessions = <Map>[
      {
        'date': '2026-10-19',
        'selfReportedHours': 7.0,
        'estimatedHours': 9.0,
        'wake': {'updatedAt': '2026-10-19T02:00:00Z'}
      }
    ];
    final old = sleep(6, '2026-10-19T01:00:00Z');
    expect(routineSummary(sessions, [old])['averageSleepHours'], 7);
    final recent = sleep(8, '2026-10-19T03:00:00Z');
    final summary = routineSummary(sessions, [old, recent]);
    expect(summary['averageSleepHours'], 8);
    expect(summary['selfReportedSleepDays'], 1);
    expect(summary['estimatedRestDays'], 0);
    expect(
        mergeRoutineSleep(sessions, [old, recent]).single['selfReportedHours'],
        8);
  });
  test('legacy only and missing days do not invent zero sleep', () {
    final rows = mergeRoutineSleep([], [sleep(6.5, '2026-10-19T03:00:00Z')]);
    expect(rows.single['sleepSource'], '历史手工记录');
    expect(routineSummary([], [])['averageSleepHours'], isNull);
    expect(
        routineSummary([
          {'date': '2026-10-19', 'wake': {}}
        ], [])['estimatedRestDays'],
        0);
  });
}
