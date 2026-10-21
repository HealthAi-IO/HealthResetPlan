import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'routine_service.dart';

class RoutineChart extends StatelessWidget {
  const RoutineChart(
      {super.key,
      required this.rows,
      required this.days,
      required this.endDate,
      this.target});
  final List<Map> rows;
  final int days;
  final String endDate;
  final num? target;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final end = DateTime.parse(endDate);
    final dates = List.generate(
        days,
        (index) => DateFormat('yyyy-MM-dd')
            .format(end.subtract(Duration(days: days - 1 - index))));
    final byDate = {for (final row in rows) row['date'] as String: row};
    final valid = rows
        .where((row) =>
            row['selfReportedHours'] != null || row['estimatedHours'] != null)
        .toList();
    final reached = target == null
        ? 0
        : valid
            .where((row) =>
                ((row['selfReportedHours'] ?? row['estimatedHours']) as num) >=
                target!)
            .length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          '有效时长 ${valid.length} 天 / $days 天${target == null ? '' : ' · 达到休息目标 $reached 天'}'),
      if (valid.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('还没有可展示的休息时长。记录晚安和次日起床，或在起床记录中确认实际睡眠。'),
        ),
      if (valid.isNotEmpty) ...[
      const Text('时长（小时） · 空白表示未记录'),
      const SizedBox(height: 12),
      SizedBox(
          height: 180,
          child: CustomPaint(
              size: const Size(double.infinity, 180),
              painter: _RestPainter(dates.map((date) => byDate[date]).toList(),
                  colors, target?.toDouble()))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(dates.first.substring(5)),
        Text(dates.last.substring(5))
      ]),
      Text('● 自报睡眠   ▬ 估算休息${target == null ? '' : '   ┄ 目标 $target 小时'}',
          style: TextStyle(color: colors.primary)),
      ],
      const SizedBox(height: 20),
      Text('作息时刻 · 夜间连续时间轴', style: Theme.of(context).textTheme.titleMedium),
      const Text('中午 12:00 → 午夜 00:00 → 次日中午 12:00'),
      for (final row in rows.where((row) => row['wake'] != null))
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(
                  width: 54, child: Text((row['date'] as String).substring(5))),
              Expanded(
                  child: SizedBox(
                      height: 26,
                      child: LayoutBuilder(builder: (context, constraints) {
                        final wake = beijingTime(
                            DateTime.parse((row['wake'] as Map)['occurredAt']));
                        final wakeHour = wake.hour + wake.minute / 60;
                        final wakePosition =
                            ((wakeHour < 12 ? wakeHour + 24 : wakeHour) - 12) /
                                24;
                        final bed = row['bed'] == null
                            ? null
                            : beijingTime(DateTime.parse(
                                (row['bed'] as Map)['occurredAt']));
                        final bedHour =
                            bed == null ? null : bed.hour + bed.minute / 60;
                        final bedPosition = bedHour == null
                            ? null
                            : ((bedHour < 12 ? bedHour + 24 : bedHour) - 12) /
                                24;
                        return Stack(clipBehavior: Clip.none, children: [
                          Center(
                              child: Container(
                                  height: 2, color: colors.outlineVariant)),
                          if (bedPosition != null)
                            Positioned(
                                left: bedPosition * (constraints.maxWidth - 20),
                                child: Icon(Icons.bedtime,
                                    size: 20, color: colors.secondary)),
                          Positioned(
                              left: wakePosition * (constraints.maxWidth - 20),
                              child: Icon(Icons.wb_sunny,
                                  size: 20, color: colors.primary)),
                        ]);
                      }))),
              const SizedBox(width: 8),
              Flexible(child: Text(
                  '${row['bed'] == null ? '缺晚安' : DateFormat('HH:mm').format(beijingTime(DateTime.parse((row['bed'] as Map)['occurredAt'])))} / ${DateFormat('HH:mm').format(beijingTime(DateTime.parse((row['wake'] as Map)['occurredAt'])))}',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall)),
            ])),
    ]);
  }
}

class _RestPainter extends CustomPainter {
  _RestPainter(this.rows, this.colors, this.target);
  final List<Map?> rows;
  final ColorScheme colors;
  final double? target;
  @override
  void paint(Canvas canvas, Size size) {
    const maxHours = 24.0;
    const left = 26.0;
    final width = size.width - left;
    for (final hour in [0, 8, 16, 24]) {
      final y = size.height - 8 - hour / maxHours * (size.height - 20);
      canvas.drawLine(Offset(left, y), Offset(size.width, y),
          Paint()..color = colors.outlineVariant);
      final text = TextPainter(
          text: TextSpan(
              text: '$hour',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          textDirection: ui.TextDirection.ltr)
        ..layout();
      text.paint(canvas, Offset(0, y - 7));
    }
    if (target != null) {
      final y = size.height - 8 - target! / maxHours * (size.height - 20);
      for (double x = left; x < size.width; x += 8) {
        canvas.drawLine(
            Offset(x, y),
            Offset((x + 4).clamp(left, size.width), y),
            Paint()
              ..color = colors.tertiary
              ..strokeWidth = 2);
      }
    }
    final step = width / rows.length;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final hours =
          (row?['selfReportedHours'] ?? row?['estimatedHours']) as num?;
      if (hours == null) continue;
      final height = hours / maxHours * (size.height - 20);
      final rect = Rect.fromLTWH(left + step * index + step * .2,
          size.height - 8 - height, step * .6, height);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()
            ..color = row?['selfReportedHours'] != null
                ? colors.primary
                : colors.secondaryContainer);
    }
  }

  @override
  bool shouldRepaint(covariant _RestPainter oldDelegate) => true;
}
