import '../../core/data/health_models.dart';
import 'routine_service.dart';

List<Map> mergeRoutineSleep(
    List<Map> sessions, List<HealthIndicatorEntry> indicators) {
  final rows = {
    for (final row in sessions)
      row['date'] as String: Map<String, dynamic>.from(row)
  };
  final ordered = indicators.where((e) => e.type == 'sleep').toList()
    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  for (final entry in ordered) {
    final hours =
        (entry.payload['sleepHours'] ?? entry.payload['hours']) as num?;
    if (hours == null || !hours.isFinite || hours <= 0 || hours > 24) continue;
    final date = routineDate(entry.measuredTime);
    final row =
        rows.putIfAbsent(date, () => {'date': date, 'status': 'legacy'});
    final wake = row['wake'] as Map?;
    final updatedAt = DateTime.tryParse(wake?['updatedAt']?.toString() ?? '')
            ?.millisecondsSinceEpoch ??
        0;
    if (row['selfReportedHours'] == null || entry.updatedAt >= updatedAt) {
      row['selfReportedHours'] = hours.toDouble();
      row['sleepSource'] = '历史手工记录';
    }
  }
  return rows.values.toList()
    ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
}

Map<String, dynamic> routineSummary(
    List<Map> sessions, List<HealthIndicatorEntry> indicators) {
  final confirmed = <String, (double, int)>{};
  for (final entry in indicators.where((e) => e.type == 'sleep')) {
    final hours =
        (entry.payload['sleepHours'] ?? entry.payload['hours']) as num?;
    if (hours == null || !hours.isFinite || hours <= 0 || hours > 24) continue;
    final day = routineDate(entry.measuredTime);
    if (entry.updatedAt >= (confirmed[day]?.$2 ?? 0)) {
      confirmed[day] = (hours.toDouble(), entry.updatedAt);
    }
  }
  final estimated = <String, double>{};
  for (final session in sessions) {
    final day = session['date'] as String;
    final hours = session['selfReportedHours'] as num?;
    final updatedAt = DateTime.tryParse(
                (session['wake'] as Map)['updatedAt']?.toString() ?? '')
            ?.millisecondsSinceEpoch ??
        0;
    if (hours != null && updatedAt >= (confirmed[day]?.$2 ?? 0)) {
      confirmed[day] = (hours.toDouble(), updatedAt);
    }
    final interval = session['estimatedHours'] as num?;
    if (interval != null) estimated[day] = interval.toDouble();
  }
  estimated.removeWhere((day, _) => confirmed.containsKey(day));
  return {
    'selfReportedSleepDays': confirmed.length,
    if (confirmed.isNotEmpty)
      'averageSleepHours':
          confirmed.values.fold<double>(0, (sum, value) => sum + value.$1) /
              confirmed.length,
    'estimatedRestDays': estimated.length,
    if (estimated.isNotEmpty)
      'averageEstimatedRestHours':
          estimated.values.reduce((a, b) => a + b) / estimated.length,
    'sleepDataNote': '自报睡眠与估算休息间隔分别统计，同日不重复计算；不推断深睡或医学睡眠质量。',
  };
}
