import 'package:android_intent_plus/android_intent.dart';
import 'package:timezone/timezone.dart' as tz;

List<tz.TZDateTime> routineReminderTimes(
    Map<String, dynamic> settings, String type, tz.TZDateTime now) {
  if (settings['${type}Reminder'] != true ||
      settings['${type}Target'] == null ||
      (type == 'wake' && settings['wakeReminderMode'] == 'alarm')) {
    return [];
  }
  final time = (settings['${type}Target'] as String).split(':');
  final days =
      List<int>.from(settings['${type}ReminderDays'] ?? [1, 2, 3, 4, 5, 6, 7]);
  final lead = type == 'bed'
      ? (settings['bedReminderLeadMinutes'] as num?)?.toInt() ?? 0
      : 0;
  return days.map((weekday) {
    final offset = (weekday - now.weekday + 7) % 7;
    var next = tz.TZDateTime(now.location, now.year, now.month,
            now.day + offset, int.parse(time[0]), int.parse(time[1]))
        .subtract(Duration(minutes: lead));
    if (!next.isAfter(now)) next = next.add(const Duration(days: 7));
    return next;
  }).toList();
}

AndroidIntent routineSystemAlarm(Map<String, dynamic> settings) {
  final time = (settings['wakeTarget'] as String).split(':');
  return AndroidIntent(
    action: 'android.intent.action.SET_ALARM',
    arguments: {
      'android.intent.extra.alarm.HOUR': int.parse(time[0]),
      'android.intent.extra.alarm.MINUTES': int.parse(time[1]),
      'android.intent.extra.alarm.MESSAGE': '健康重启计划 · 起床',
      'android.intent.extra.alarm.VIBRATE': true,
      'android.intent.extra.alarm.SKIP_UI': false,
      'android.intent.extra.alarm.DAYS':
          List<int>.from(settings['wakeReminderDays'] ?? [1, 2, 3, 4, 5, 6, 7])
              .map((day) => day % 7 + 1)
              .toList(),
    },
  );
}
