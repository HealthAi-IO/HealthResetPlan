import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_settings_controller.dart';
import '../clock/clock_page.dart';
import '../stats/stats_page.dart';
import 'data_calendar_page.dart';
import 'weekly_health_report_page.dart';
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
  int _indexForView(String view) => switch (view) {
        'clock' => 0,
        'stats' => 2,
        'weekly' => 3,
        _ => 1,
      };

  late int _index = _indexForView(widget.initialView);

  String _viewForIndex(int index) => switch (index) {
        0 => 'clock',
        2 => 'stats',
        3 => 'weekly',
        _ => 'calendar',
      };

  void _selectIndex(int index) {
    if (_index != index) setState(() => _index = index);
    final view = _viewForIndex(index);
    if (GoRouterState.of(context).uri.queryParameters['view'] != view) {
      context.go('/records?view=$view');
    }
  }

  @override
  void didUpdateWidget(covariant RecordHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialView != widget.initialView) {
      _index = _indexForView(widget.initialView);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (appSettingsController.seniorMode) {
      return ClockPage(
        initialReminderId: widget.initialReminderId,
        openReminderSettings: widget.openReminderSettings,
      );
    }
    return Column(
      children: [
        const HealthPageHeader(
          title: '健康记录',
          subtitle: '回看每一次真实变化',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('打卡')),
                ButtonSegment(value: 1, label: Text('日历')),
                ButtonSegment(value: 2, label: Text('趋势')),
                ButtonSegment(value: 3, label: Text('AI周报')),
              ],
              selected: {_index},
              onSelectionChanged: (value) {
                _selectIndex(value.first);
              },
            ),
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
              StatsPage(onOpenClock: () => _selectIndex(0)),
              const WeeklyHealthReportPage(),
            ],
          ),
        ),
      ],
    );
  }
}
