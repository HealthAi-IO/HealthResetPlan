import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_settings_controller.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/feedback/clock_feedback_service.dart';
import '../meals/meal_input_args.dart';
import '../stats/stats_page.dart';
import 'data_calendar_page.dart';
import 'weekly_health_report_page.dart';

class SeniorRecordPage extends StatefulWidget {
  const SeniorRecordPage({super.key});

  @override
  State<SeniorRecordPage> createState() => _SeniorRecordPageState();
}

class _SeniorRecordPageState extends State<SeniorRecordPage> {
  final HealthRepository _repository = sl<HealthRepository>();
  bool _loading = true;
  String? _loadError;
  List<_RecentRecord> _recent = const [];
  List<ClockRecordData> _clockRecords = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final now = DateTime.now();
      final indicators = await _repository.loadIndicators(limit: 8);
      final meals = await _repository.loadMealsBetween(
        now.subtract(const Duration(days: 30)),
        now,
      );
      final clockRecords = await _repository.loadClockRecords(limit: 60);
      final records = <_RecentRecord>[
        for (final item in indicators)
          _RecentRecord(
            title: item.label,
            detail: item.displayValue,
            time: item.measuredTime,
            icon: Icons.monitor_heart_outlined,
            onOpen: item.id == null
                ? null
                : () =>
                    context.push('/indicators/edit/${item.id}', extra: item),
          ),
        for (final item in meals)
          _RecentRecord(
            title: item.mealLabel,
            detail: item.name.trim().isEmpty ? '已记录饮食' : item.name.trim(),
            time: item.eatenTime,
            icon: Icons.restaurant_outlined,
            onOpen: () => context.push('/meals/input', extra: item),
          ),
        for (final item in clockRecords.take(20))
          if (item.type == 'water' || item.type == 'exercise')
            _RecentRecord(
              title: item.label,
              detail: item.displayDetail,
              time: item.clockTime,
              icon: item.type == 'water'
                  ? Icons.water_drop_outlined
                  : Icons.directions_walk_outlined,
              onOpen: null,
            ),
      ]..sort((a, b) => b.time.compareTo(a.time));
      if (!mounted) return;
      setState(() {
        _recent = records.take(5).toList();
        _clockRecords = clockRecords;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '记录加载失败，请稍后重试。';
      });
    }
  }

  Future<void> _recordExercise() async {
    var activity = '快走';
    var minutes = 30;
    final result = await showModalBottomSheet<({String name, int minutes})>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('记录运动',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final value in const ['快走', '慢跑', '骑行', '瑜伽', '健身操'])
                  ChoiceChip(
                    label: Text(value, style: const TextStyle(fontSize: 18)),
                    selected: activity == value,
                    onSelected: (_) => setSheetState(() => activity = value),
                  ),
              ]),
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final value in const [10, 20, 30, 45, 60])
                  ChoiceChip(
                    label:
                        Text('$value 分钟', style: const TextStyle(fontSize: 18)),
                    selected: minutes == value,
                    onSelected: (_) => setSheetState(() => minutes = value),
                  ),
              ]),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.pop(
                  sheetContext,
                  (name: activity, minutes: minutes),
                ),
                icon: const Icon(Icons.directions_walk_outlined),
                label: Text('记录 $activity $minutes 分钟'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  textStyle: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (result == null) return;
    final previous = _todayClockRecords('exercise');
    final total = previous.fold<int>(
          0,
          (sum, record) => sum + (record.exerciseMinutes ?? 0),
        ) +
        result.minutes;
    final id = await _repository.addClockRecord(
      type: 'exercise',
      note: '${result.name} ${result.minutes} 分钟',
      value: result.minutes,
      unit: 'minute',
      detail: result.name,
    );
    if (!mounted) return;
    _showSeniorResult(
      title: '${result.name} ${result.minutes} 分钟，已经记下了',
      detail: '今天累计 $total 分钟',
      icon: Icons.directions_walk_outlined,
      recordId: id,
    );
    await ClockFeedbackService.acknowledge(
      message: '已记录${result.name}${result.minutes}分钟，今天累计$total分钟',
      speak: appSettingsController.seniorClockVoice,
    );
    await _load();
  }

  Future<void> _recordWater() async {
    var amount = 200;
    final result = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('记录饮水',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final value in const [100, 200, 300, 500, 750])
                  ChoiceChip(
                    label:
                        Text('$value 毫升', style: const TextStyle(fontSize: 18)),
                    selected: amount == value,
                    onSelected: (_) => setSheetState(() => amount = value),
                  ),
              ]),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.pop(sheetContext, amount),
                icon: const Icon(Icons.water_drop_outlined),
                label: Text('记录 $amount 毫升'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  textStyle: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (result == null) return;
    final previous = _todayClockRecords('water');
    final previousTotal = previous.fold<int>(
      0,
      (sum, record) => sum + (record.waterMilliliters ?? 0),
    );
    final total = previousTotal + result;
    final id = await _repository.addClockRecord(
      type: 'water',
      note: '饮水 $result ml',
      value: result,
      unit: 'ml',
    );
    if (!mounted) return;
    final goal = appSettingsController.waterGoalMl;
    _showSeniorResult(
      title: '已记录饮水 $result 毫升',
      detail: goal == null ? '今天累计 $total 毫升' : '今天已喝 $total / $goal 毫升',
      icon: Icons.water_drop_outlined,
      recordId: id,
    );
    await ClockFeedbackService.acknowledge(
      message: '已记录饮水$result毫升，今天累计$total毫升',
      speak: appSettingsController.seniorClockVoice,
    );
    await _load();
  }

  List<ClockRecordData> _todayClockRecords(String type) {
    final now = DateTime.now();
    return _clockRecords.where((record) {
      final time = record.clockTime;
      return record.type == type &&
          record.status == 'done' &&
          time.year == now.year &&
          time.month == now.month &&
          time.day == now.day;
    }).toList();
  }

  void _showSeniorResult({
    required String title,
    required String detail,
    required IconData icon,
    required int recordId,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Semantics(
          liveRegion: true,
          child: Row(children: [
            Icon(icon, color: Theme.of(context).colorScheme.inversePrimary),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                Text(detail, style: const TextStyle(fontSize: 17)),
              ],
            )),
          ]),
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await _repository.deleteClockRecord(recordId);
            await _load();
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const PageStorageKey('senior-record-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 104),
        children: [
          const Text(
            '记录健康',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '选择你现在要记录的内容',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('我要记录'),
          const SizedBox(height: 10),
          _RecordAction(
            icon: Icons.restaurant_outlined,
            title: '记录饮食',
            description: '早餐、午餐、晚餐或加餐',
            onTap: () => context
                .push(
                  '/meals/input',
                  extra: MealInputArgs(
                    mealType: _currentMealType(),
                    eatenDate: DateTime.now(),
                  ),
                )
                .then((_) => _load()),
          ),
          _RecordAction(
            icon: Icons.monitor_heart_outlined,
            title: '健康测量',
            description: '血压、血糖、体重等数据',
            onTap: () => context.push('/indicators/input').then((_) => _load()),
          ),
          _RecordAction(
            icon: Icons.medication_outlined,
            title: '确认用药',
            description: '进入提醒，逐项确认已服或跳过',
            onTap: () => context.go('/meals'),
          ),
          _RecordAction(
            icon: Icons.directions_walk_outlined,
            title: '记录运动',
            description: '确认一次已经完成的运动',
            onTap: _recordExercise,
          ),
          _RecordAction(
            icon: Icons.water_drop_outlined,
            title: '记录饮水',
            description: '选择这次喝了多少水',
            onTap: _recordWater,
          ),
          const SizedBox(height: 22),
          const _SectionTitle('最近记录'),
          const SizedBox(height: 10),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_loadError != null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                Text(_loadError!,
                    style: TextStyle(color: colors.onErrorContainer)),
                const SizedBox(height: 8),
                TextButton(onPressed: _load, child: const Text('重新加载')),
              ]),
            )
          else if (_recent.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('还没有记录，可以从第一次测量开始。'),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < _recent.length; index++) ...[
                    _RecentRecordTile(record: _recent[index]),
                    if (index != _recent.length - 1)
                      Divider(height: 1, color: colors.outlineVariant),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 22),
          const _SectionTitle('查看历史'),
          const SizedBox(height: 10),
          _HistoryAction(
            icon: Icons.calendar_month_outlined,
            label: '按日历查看',
            onTap: () => context.push('/record-history/calendar'),
          ),
          _HistoryAction(
            icon: Icons.insights_outlined,
            label: '查看健康趋势',
            onTap: () => context.push('/record-history/stats'),
          ),
          _HistoryAction(
            icon: Icons.auto_awesome_outlined,
            label: 'AI 健康周报',
            onTap: () => context.push('/record-history/weekly'),
          ),
        ],
      ),
    );
  }
}

String _currentMealType() {
  final hour = DateTime.now().hour;
  if (hour < 10) return 'breakfast';
  if (hour < 15) return 'lunch';
  if (hour < 21) return 'dinner';
  return 'snack';
}

class SeniorCalendarPage extends StatelessWidget {
  const SeniorCalendarPage({super.key});

  @override
  Widget build(BuildContext context) => const RecordHistoryPage(
        title: '按日历查看',
        view: DataCalendarPage(),
      );
}

class SeniorStatsPage extends StatelessWidget {
  const SeniorStatsPage({super.key});

  @override
  Widget build(BuildContext context) => RecordHistoryPage(
        title: '健康趋势',
        view: StatsPage(onOpenClock: () => context.go('/meals')),
      );
}

class SeniorWeeklyReportPage extends StatelessWidget {
  const SeniorWeeklyReportPage({super.key});

  @override
  Widget build(BuildContext context) => const RecordHistoryPage(
        title: 'AI 健康周报',
        view: WeeklyHealthReportPage(),
      );
}

class RecordHistoryPage extends StatelessWidget {
  const RecordHistoryPage({
    super.key,
    required this.title,
    required this.view,
  });

  final String title;
  final Widget view;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: view,
    );
  }
}

class _RecordAction extends StatelessWidget {
  const _RecordAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Icon(icon, size: 30, color: colors.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(description,
                          style: TextStyle(color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      );
}

class _RecentRecordTile extends StatelessWidget {
  const _RecentRecordTile({required this.record});

  final _RecentRecord record;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 82,
      leading: Icon(record.icon, size: 28),
      title: Text(record.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${record.detail}\n${DateFormat('M月d日 HH:mm').format(record.time)}',
      ),
      isThreeLine: true,
      trailing: record.onOpen == null ? null : const Text('修改'),
      onTap: record.onOpen,
    );
  }
}

class _HistoryAction extends StatelessWidget {
  const _HistoryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        minTileHeight: 64,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(icon, size: 28),
        title: Text(label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

class _RecentRecord {
  const _RecentRecord({
    required this.title,
    required this.detail,
    required this.time,
    required this.icon,
    required this.onOpen,
  });

  final String title;
  final String detail;
  final DateTime time;
  final IconData icon;
  final VoidCallback? onOpen;
}
