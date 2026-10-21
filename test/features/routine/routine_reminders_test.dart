import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/features/routine/routine_reminders.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  data.initializeTimeZones();
  final zone = tz.getLocation('Asia/Shanghai');
  test('system clock receives actual target and Android weekday numbering', () {
    final intent = routineSystemAlarm({
      'wakeTarget': '07:25',
      'wakeReminderDays': [1, 5, 7],
    });
    expect(intent.action, 'android.intent.action.SET_ALARM');
    expect(intent.arguments?['android.intent.extra.alarm.HOUR'], 7);
    expect(intent.arguments?['android.intent.extra.alarm.MINUTES'], 25);
    expect(intent.arguments?['android.intent.extra.alarm.DAYS'], [2, 6, 1]);
    expect(intent.arguments?['android.intent.extra.alarm.SKIP_UI'], false);
  });
  test('legacy enabled reminder repeats daily and skips elapsed times', () {
    final times = routineReminderTimes({
      'wakeTarget': '07:00',
      'wakeReminder': true,
    }, 'wake', tz.TZDateTime(zone, 2026, 10, 19, 8));
    expect(times.length, 7);
    expect(times.every((time) => time.hour == 7 && time.minute == 0), isTrue);
    expect(times.map((time) => time.day), contains(26));
  });
  test('workdays excludes weekends and clock mode creates no app reminders',
      () {
    final settings = <String, dynamic>{
      'wakeTarget': '07:00',
      'wakeReminder': true,
      'wakeReminderDays': [1, 2, 3, 4, 5],
    };
    final now = tz.TZDateTime(zone, 2026, 10, 23, 8);
    final times = routineReminderTimes(settings, 'wake', now);
    expect(times.length, 5);
    expect(
        times.every((time) => time.weekday <= 5 && time.isAfter(now)), isTrue);
    settings['wakeReminderMode'] = 'alarm';
    expect(routineReminderTimes(settings, 'wake', now), isEmpty);
  });
  test('bed lead crosses midnight according to target weekday', () {
    final settings = <String, dynamic>{
      'bedTarget': '00:10',
      'bedReminder': true,
      'bedReminderDays': [1],
      'bedReminderLeadMinutes': 30,
    };
    final times = routineReminderTimes(
        settings, 'bed', tz.TZDateTime(zone, 2026, 10, 18, 23));
    expect(times.single, tz.TZDateTime(zone, 2026, 10, 18, 23, 40));
    final elapsed = routineReminderTimes(
        settings, 'bed', tz.TZDateTime(zone, 2026, 10, 18, 23, 50));
    expect(elapsed.single, tz.TZDateTime(zone, 2026, 10, 25, 23, 40));
  });
  test('disabled or cleared goal creates no notifications', () {
    final now = tz.TZDateTime(zone, 2026, 10, 19);
    expect(routineReminderTimes({'bedTarget': '23:00'}, 'bed', now), isEmpty);
    expect(routineReminderTimes({'bedReminder': true}, 'bed', now), isEmpty);
  });
}
