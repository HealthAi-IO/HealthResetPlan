import 'package:flutter/material.dart';

import '../clock/clock_page.dart';
import '../stats/stats_page.dart';
import 'data_calendar_page.dart';
import '../../core/widgets/health_ui.dart';

class RecordHubPage extends StatefulWidget {
  const RecordHubPage({
    super.key,
    this.initialView = 'clock',
    this.initialReminderId,
    this.openReminderSettings = false,
  });

  final String initialView;
  final int? initialReminderId;
  final bool openReminderSettings;

  @override
  State<RecordHubPage> createState() => _RecordHubPageState();
}

class _RecordHubPageState extends State<RecordHubPage> {
  late int _index = widget.initialView == 'stats' ? 2 : 1;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const HealthPageHeader(
          title: '健康记录',
          subtitle: '回看每一次真实变化',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.check_circle_outline),
                label: Text('今日打卡'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.calendar_month_outlined),
                label: Text('数据日历'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.insights_outlined),
                label: Text('趋势分析'),
              ),
            ],
            selected: {_index},
            onSelectionChanged: (value) {
              setState(() => _index = value.first);
            },
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              ClockPage(
                initialReminderId: widget.initialReminderId,
                openReminderSettings: widget.openReminderSettings,
              ),
              const DataCalendarPage(),
              const StatsPage(),
            ],
          ),
        ),
      ],
    );
  }
}
