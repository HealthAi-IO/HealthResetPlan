import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/data/health_repository.dart';
import '../../core/data/health_models.dart';
import '../../core/di/service_locator.dart';
import '../../core/notification/reminder_scheduler.dart';
import 'quit_smoking_models.dart';
import 'quit_smoking_repository.dart';

class QuitSmokingPage extends StatefulWidget {
  const QuitSmokingPage({super.key});

  @override
  State<QuitSmokingPage> createState() => _QuitSmokingPageState();
}

class _QuitSmokingPageState extends State<QuitSmokingPage> {
  final _repository = sl<QuitSmokingRepository>();
  QuitSmokingProfile? _profile;
  List<QuitSmokingEvent> _events = const [];
  bool _loading = true;
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _repository.loadProfile();
    final events = await _repository.loadEvents();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _events = events;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_profile == null) {
      return _SetupView(onSaved: _load);
    }
    final profile = _profile!;
    final cravings = _events.where((event) => event.type == QuitSmokingEventType.craving);
    final progress = calculateQuitSmokingProgress(
      profile: profile,
      events: _events,
      now: _now,
    );
    final successCravings = cravings.where((event) => event.success == true).length;
    final checkedInToday = _events.any((event) {
      if (event.type != QuitSmokingEventType.checkIn) return false;
      final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
      return time.year == _now.year && time.month == _now.month && time.day == _now.day;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('戒烟计划'),
        actions: [
          IconButton(
            tooltip: '调整计划',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => _SetupView(profile: profile, onSaved: _load)),
              );
            },
            icon: const Icon(Icons.tune_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _SummaryPanel(
              progress: progress,
              todayCount: progress.todayCount,
              target: profile.mode == QuitSmokingMode.gradual ? profile.stageGoal : 0,
              checkedInToday: checkedInToday,
              onCheckIn: _checkIn,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _recordSmoked(),
                    icon: const Icon(Icons.smoke_free),
                    label: const Text('记录一次吸烟'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _recordCraving(),
                    icon: const Icon(Icons.self_improvement_outlined),
                    label: const Text('我想抽烟'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _AdvicePanel(),
            const SizedBox(height: 12),
            _SevenDayTrack(
              profile: profile,
              events: _events,
              now: _now,
            ),
            const SizedBox(height: 12),
            _HealthMilestonesPanel(
              elapsed: _now.isBefore(progress.startedAt)
                  ? Duration.zero
                  : _now.difference(progress.startedAt),
            ),
            const SizedBox(height: 12),
            _StatsPanel(
              events: _events,
              baseline: profile.dailyBaseline,
              cravingSuccessRate: cravings.isEmpty ? 0 : successCravings / cravings.length,
            ),
            const SizedBox(height: 12),
            _RecentEvents(events: _events.take(12).toList()),
          ],
        ),
      ),
    );
  }

  Future<void> _recordSmoked() async {
    final result = await showDialog<_EventInput>(
      context: context,
      builder: (_) => const _SmokedDialog(),
    );
    if (result == null) return;
    await _repository.addEvent(
      type: QuitSmokingEventType.smoked,
      cigarettes: result.cigarettes,
      intensity: result.intensity,
      success: null,
      trigger: result.trigger,
      strategy: '',
      note: result.note,
    );
    await _load();
  }

  Future<void> _recordCraving() async {
    final result = await showDialog<_CravingResult>(
      context: context,
      builder: (_) => const _CravingDialog(),
    );
    if (result == null) return;
    await _repository.addEvent(
      type: QuitSmokingEventType.craving,
      cigarettes: 0,
      intensity: result.intensity,
      success: result.success,
      trigger: result.trigger,
      strategy: result.strategy,
      note: result.note,
    );
    await _load();
  }

  Future<void> _checkIn() async {
    final alreadyChecked = _events.any((event) {
      if (event.type != QuitSmokingEventType.checkIn) return false;
      final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
      return time.year == _now.year && time.month == _now.month && time.day == _now.day;
    });
    if (alreadyChecked) return;
    await _repository.addEvent(
      type: QuitSmokingEventType.checkIn,
      cigarettes: 0,
      intensity: 0,
      success: true,
      trigger: '',
      strategy: '',
      note: '',
    );
    await _load();
  }

}

class _SetupView extends StatefulWidget {
  const _SetupView({this.profile, required this.onSaved});

  final QuitSmokingProfile? profile;
  final Future<void> Function() onSaved;

  @override
  State<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<_SetupView> {
  final _baseline = TextEditingController();
  final _packCigarettes = TextEditingController(text: '20');
  final _packPrice = TextEditingController();
  final _smokingYears = TextEditingController();
  final _stageGoal = TextEditingController();
  final _motivation = TextEditingController();
  final _triggers = TextEditingController();
  QuitSmokingMode _mode = QuitSmokingMode.immediate;
  DateTime _targetDate = DateTime.now();
  bool _remindersEnabled = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    if (profile == null) return;
    _mode = profile.mode;
    _baseline.text = '${profile.dailyBaseline}';
    _packCigarettes.text = '${profile.packCigarettes}';
    _packPrice.text = '${profile.packPrice}';
    _smokingYears.text = '${profile.smokingYears}';
    _stageGoal.text = '${profile.stageGoal}';
    _motivation.text = profile.motivation;
    _triggers.text = profile.triggers.join('、');
    _targetDate = DateTime.fromMillisecondsSinceEpoch(profile.targetDate);
    _remindersEnabled = profile.remindersEnabled;
  }

  @override
  void dispose() {
    for (final controller in [_baseline, _packCigarettes, _packPrice, _smokingYears, _stageGoal, _motivation, _triggers]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final embedded = widget.profile != null;
    return Scaffold(
      appBar: embedded ? AppBar(title: const Text('调整戒烟计划')) : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          if (!embedded) ...[
            Text('开始你的戒烟计划', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('先记录基础情况，后续的目标和统计会根据你的实际记录调整。'),
            const SizedBox(height: 24),
          ],
          SegmentedButton<QuitSmokingMode>(
            segments: const [
              ButtonSegment(value: QuitSmokingMode.immediate, label: Text('立即戒烟')),
              ButtonSegment(value: QuitSmokingMode.gradual, label: Text('逐步减少')),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
          const SizedBox(height: 16),
          _numberField(_baseline, '平均每天吸烟（支）', required: true),
          _numberField(_packCigarettes, '每包支数', required: true),
          _numberField(_packPrice, '每包价格（元）', required: true),
          _numberField(_smokingYears, '吸烟年限（年，可选）'),
          if (_mode == QuitSmokingMode.gradual)
            _numberField(_stageGoal, '当前阶段每日目标（支）', required: true),
          TextField(
            controller: _motivation,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '戒烟动机（可选）', hintText: '例如：改善体力、陪伴家人'),
          ),
          TextField(
            controller: _triggers,
            decoration: const InputDecoration(
              labelText: '常见诱因（可选）',
              hintText: '例如：饭后、压力、社交，用顿号分隔',
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('目标戒烟日期'),
            subtitle: Text(_dateText(_targetDate)),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: _pickTargetDate,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开启戒烟提醒'),
            subtitle: const Text('每天晚上 8 点提醒记录今天的情况'),
            value: _remindersEnabled,
            onChanged: (value) => setState(() => _remindersEnabled = value),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('保存戒烟计划')),
        ],
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: required ? '*' : null),
      ),
    );
  }

  Future<void> _pickTargetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate.isBefore(DateTime.now()) ? DateTime.now() : _targetDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    final baseline = int.tryParse(_baseline.text.trim()) ?? 0;
    final packCigarettes = int.tryParse(_packCigarettes.text.trim()) ?? 0;
    final packPrice = double.tryParse(_packPrice.text.trim()) ?? 0;
    if (baseline <= 0 || packCigarettes <= 0 || packPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写有效的每日支数、每包支数和每包价格')),
      );
      return;
    }
    await sl<QuitSmokingRepository>().saveProfile(
      mode: _mode,
      dailyBaseline: baseline,
      packCigarettes: packCigarettes,
      packPrice: packPrice,
      smokingYears: int.tryParse(_smokingYears.text.trim()) ?? 0,
      targetDate: _targetDate,
      motivation: _motivation.text.trim(),
      triggers: _triggers.text
          .split('、')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      stageGoal: _mode == QuitSmokingMode.gradual
          ? (int.tryParse(_stageGoal.text.trim()) ?? (baseline - 1)).clamp(1, baseline)
          : 0,
      stageStartDate: DateTime.now(),
      remindersEnabled: _remindersEnabled,
    );
    await _syncReminder(_remindersEnabled);
    await widget.onSaved();
    if (mounted && widget.profile != null) Navigator.of(context).pop();
  }

  Future<void> _syncReminder(bool enabled) async {
    final healthRepository = sl<HealthRepository>();
    final existing = (await healthRepository.loadReminders())
        .where((reminder) => reminder.type == 'quit_smoking')
        .toList();
    if (!enabled) {
      for (final reminder in existing) {
        await healthRepository.setReminderEnabled(reminder, false);
      }
      return;
    }
    if (existing.isNotEmpty) {
      for (final reminder in existing) {
        await healthRepository.setReminderEnabled(reminder, true);
        await sl<ReminderScheduler>().syncReminder(reminder);
      }
      return;
    }
    final reminder = await healthRepository.addReminder(
      type: 'quit_smoking',
      time: const TimeOfDayValue(hour: 20, minute: 0),
      date: DateTime.now(),
      scheduleMode: 'weekly',
      weekdays: const [1, 2, 3, 4, 5, 6, 7],
      note: '记录今天的戒烟情况',
      imageObjectKey: '',
      imageMimeType: '',
      syncAlarm: false,
    );
    await sl<ReminderScheduler>().syncReminder(reminder);
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.progress,
    required this.todayCount,
    required this.target,
    required this.checkedInToday,
    required this.onCheckIn,
  });

  final QuitSmokingProgress progress;
  final int todayCount;
  final int target;
  final bool checkedInToday;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(_stageName(progress.smokeFreeDays), style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    tooltip: '节省金额说明',
                    onPressed: () => _showSavingsInfo(context, progress),
                    icon: const Icon(Icons.info_outline, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('已坚持', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                _durationText(DateTime.now().difference(progress.startedAt)),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _Metric(label: '累计少吸', value: '${progress.avoidedCigarettes} 支')),
                  Expanded(child: _Metric(label: '累计节省', value: '¥${progress.savedMoney.toStringAsFixed(2)}')),
                  Expanded(child: _Metric(label: '今日支数', value: '$todayCount${target > 0 ? ' / $target' : ''}')),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '今日预计节省 ¥${progress.todaySavedMoney.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: checkedInToday ? null : onCheckIn,
                    icon: Icon(checkedInToday ? Icons.check : Icons.task_alt_outlined, size: 18),
                    label: Text(checkedInToday ? '今日已打卡' : '今日打卡'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]);
}

class _AdvicePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.lightbulb_outline),
          title: const Text('今天的应对建议'),
          subtitle: const Text('想抽烟时先延迟 90 秒，喝水并离开触发环境。渴望通常会逐渐减弱。'),
        ),
      );
}

class _SevenDayTrack extends StatelessWidget {
  const _SevenDayTrack({
    required this.profile,
    required this.events,
    required this.now,
  });

  final QuitSmokingProfile profile;
  final List<QuitSmokingEvent> events;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(7, (index) => today.subtract(Duration(days: 6 - index)));
    final target = profile.mode == QuitSmokingMode.gradual ? profile.stageGoal : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最近 7 天', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('打卡后确认当天是否达到目标', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final day in days)
                  _DayStatus(
                    day: day,
                    today: today,
                    checked: _hasCheckIn(day),
                    achieved: _smokedCount(day) <= target,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _hasCheckIn(DateTime day) => events.any((event) {
        if (event.type != QuitSmokingEventType.checkIn) return false;
        final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
        return time.year == day.year && time.month == day.month && time.day == day.day;
      });

  int _smokedCount(DateTime day) => events
      .where((event) {
        if (event.type != QuitSmokingEventType.smoked) return false;
        final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
        return time.year == day.year && time.month == day.month && time.day == day.day;
      })
      .fold<int>(0, (sum, event) => sum + event.cigarettes);
}

class _DayStatus extends StatelessWidget {
  const _DayStatus({required this.day, required this.today, required this.checked, required this.achieved});

  final DateTime day;
  final DateTime today;
  final bool checked;
  final bool achieved;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = checked
        ? (achieved ? Colors.teal : colors.error)
        : colors.outlineVariant;
    return SizedBox(
      width: 40,
      child: Column(
        children: [
          Text(_weekday(day.weekday), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 7),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: checked ? color : Colors.transparent,
              border: Border.all(color: color, width: day == today ? 2 : 1),
            ),
            child: Icon(
              checked ? (achieved ? Icons.check : Icons.close) : Icons.circle,
              size: checked ? 20 : 6,
              color: checked ? Colors.white : color,
            ),
          ),
          const SizedBox(height: 5),
          Text('${day.day}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _HealthMilestonesPanel extends StatelessWidget {
  const _HealthMilestonesPanel({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final completed = _healthMilestones.where((item) => elapsed >= item.duration).length;
    final next = _healthMilestones.where((item) => elapsed < item.duration).firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('健康变化参考', style: Theme.of(context).textTheme.titleMedium)),
                TextButton(
                  onPressed: () => _showMilestones(context, elapsed),
                  child: const Text('查看全部'),
                ),
              ],
            ),
            Text('已完成 $completed / ${_healthMilestones.length} 个时间里程碑'),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: completed / _healthMilestones.length),
            const SizedBox(height: 12),
            Text(
              next == null ? '已达到当前全部参考里程碑' : '下一里程碑：${next.timeLabel} · ${next.title}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              '健康科普参考，不代表个人诊断或恢复比例。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthMilestone {
  const _HealthMilestone(this.duration, this.timeLabel, this.title, this.description);

  final Duration duration;
  final String timeLabel;
  final String title;
  final String description;
}

const _healthMilestones = [
  _HealthMilestone(Duration(minutes: 20), '约 20 分钟', '身体开始适应无烟状态', '心率与循环开始进入调整阶段。'),
  _HealthMilestone(Duration(hours: 12), '约 12 小时', '一氧化碳相关指标进入调整', '身体逐步减少烟草燃烧产物带来的影响。'),
  _HealthMilestone(Duration(days: 2), '约 48 小时', '感官进入恢复阶段', '部分人的嗅觉和味觉可能逐渐改善。'),
  _HealthMilestone(Duration(days: 14), '约 2 周', '循环与呼吸持续调整', '持续戒烟有助于循环和肺功能逐步改善。'),
  _HealthMilestone(Duration(days: 90), '约 3 个月', '稳定维持阶段', '长期坚持有助于巩固无烟习惯和身体适应。'),
  _HealthMilestone(Duration(days: 365), '约 1 年', '长期健康获益阶段', '与吸烟相关的健康风险会随持续戒烟逐步下降。'),
];

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.events, required this.baseline, required this.cravingSuccessRate});
  final List<QuitSmokingEvent> events;
  final int baseline;
  final double cravingSuccessRate;
  @override
  Widget build(BuildContext context) {
    final smoked = events.where((event) => event.type == QuitSmokingEventType.smoked);
    final last7 = DateTime.now().subtract(const Duration(days: 7));
    final count = smoked.where((event) => event.occurredAt >= last7.millisecondsSinceEpoch).fold<int>(0, (sum, event) => sum + event.cigarettes);
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('近 7 天'), TextButton(onPressed: () {}, child: const Text('趋势'))]),
      Text('共记录 $count 支，基线约 ${baseline * 7} 支'),
      const SizedBox(height: 8),
      Text('渴望成功应对率 ${(cravingSuccessRate * 100).toStringAsFixed(0)}%'),
    ])));
  }
}

class _RecentEvents extends StatelessWidget {
  const _RecentEvents({required this.events});
  final List<QuitSmokingEvent> events;
  @override
  Widget build(BuildContext context) => Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.fromLTRB(18, 16, 18, 8), child: Text('最近记录', style: TextStyle(fontWeight: FontWeight.w700))),
        if (events.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('还没有记录。')),
        for (final event in events)
          ListTile(
            dense: true,
            leading: Icon(switch (event.type) {
              QuitSmokingEventType.smoked => Icons.smoke_free,
              QuitSmokingEventType.craving => Icons.self_improvement_outlined,
              QuitSmokingEventType.checkIn => Icons.task_alt_outlined,
            }),
            title: Text(switch (event.type) {
              QuitSmokingEventType.smoked => '吸烟 ${event.cigarettes} 支',
              QuitSmokingEventType.craving => event.success == true ? '成功应对渴望' : '记录一次渴望',
              QuitSmokingEventType.checkIn => '完成今日戒烟打卡',
            }),
            subtitle: Text('${_dateText(DateTime.fromMillisecondsSinceEpoch(event.occurredAt))}${event.trigger.isEmpty ? '' : ' · ${event.trigger}'}'),
          ),
      ]));
}

class _EventInput {
  const _EventInput({required this.cigarettes, required this.intensity, required this.trigger, required this.note});
  final int cigarettes;
  final int intensity;
  final String trigger;
  final String note;
}

class _SmokedDialog extends StatefulWidget {
  const _SmokedDialog();
  @override
  State<_SmokedDialog> createState() => _SmokedDialogState();
}

class _SmokedDialogState extends State<_SmokedDialog> {
  final cigarettes = TextEditingController(text: '1');
  final trigger = TextEditingController();
  final note = TextEditingController();
  int intensity = 0;
  @override
  void dispose() { cigarettes.dispose(); trigger.dispose(); note.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('记录一次吸烟'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: cigarettes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '支数', suffixText: '支')),
        TextField(controller: trigger, decoration: const InputDecoration(labelText: '诱因（可选）')),
        TextField(controller: note, decoration: const InputDecoration(labelText: '备注（可选）')),
      ]),), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, _EventInput(cigarettes: int.tryParse(cigarettes.text) ?? 1, intensity: intensity, trigger: trigger.text.trim(), note: note.text.trim())), child: const Text('保存'))]);
}

class _CravingResult {
  const _CravingResult({required this.intensity, required this.success, required this.trigger, required this.strategy, required this.note});
  final int intensity;
  final bool success;
  final String trigger;
  final String strategy;
  final String note;
}

class _CravingDialog extends StatefulWidget {
  const _CravingDialog();
  @override
  State<_CravingDialog> createState() => _CravingDialogState();
}

class _CravingDialogState extends State<_CravingDialog> {
  final trigger = TextEditingController();
  final note = TextEditingController();
  int intensity = 3;
  bool success = true;
  String strategy = '延迟 90 秒';
  @override
  void dispose() { trigger.dispose(); note.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('应对一次渴望'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('渴望强度 $intensity / 5'),
        Slider(value: intensity.toDouble(), min: 1, max: 5, divisions: 4, onChanged: (value) => setState(() => intensity = value.round())),
        DropdownButtonFormField<String>(initialValue: strategy, decoration: const InputDecoration(labelText: '应对方式'), items: const ['延迟 90 秒', '深呼吸', '喝水', '走动', '离开触发环境'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => setState(() => strategy = value ?? strategy)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('已挺过这次渴望'), value: success, onChanged: (value) => setState(() => success = value)),
        TextField(controller: trigger, decoration: const InputDecoration(labelText: '诱因（可选）')),
        TextField(controller: note, decoration: const InputDecoration(labelText: '备注（可选）')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, _CravingResult(intensity: intensity, success: success, trigger: trigger.text.trim(), strategy: strategy, note: note.text.trim())), child: const Text('保存'))]);
}

String _durationText(Duration value) {
  final duration = value.isNegative ? Duration.zero : value;
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24).toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$days 天  $hours:$minutes:$seconds';
}

String _stageName(int days) {
  if (days >= 365) return '一年里程碑';
  if (days >= 180) return '半年里程碑';
  if (days >= 90) return '三月里程碑';
  if (days >= 30) return '坚持一月';
  if (days >= 7) return '稳定一周';
  return '戒烟起步';
}

String _weekday(int value) => const ['一', '二', '三', '四', '五', '六', '日'][value - 1];

void _showSavingsInfo(BuildContext context, QuitSmokingProgress progress) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('预计节省说明'),
      content: Text(
        '累计节省按“计划开始后的基线应吸支数 - 实际吸烟支数”计算，再乘以每支价格。'
        '\n\n当前已少吸约 ${progress.avoidedCigarettes} 支，预计节省 ¥${progress.savedMoney.toStringAsFixed(2)}。'
        '\n修改每包价格后，历史金额会按新价格重新计算。',
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
      ],
    ),
  );
}

void _showMilestones(BuildContext context, Duration elapsed) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text('健康变化参考', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('以下为一般健康科普时间范围，个体变化可能不同，不代表个人诊断或恢复比例。'),
            const SizedBox(height: 16),
            for (final item in _healthMilestones)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  elapsed >= item.duration ? Icons.check_circle : Icons.schedule_outlined,
                  color: elapsed >= item.duration ? Colors.teal : null,
                ),
                title: Text('${item.timeLabel} · ${item.title}'),
                subtitle: Text(item.description),
              ),
            const Divider(),
            Text('内容参考：世界卫生组织及公共卫生机构戒烟健康资料。', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

String _dateText(DateTime value) => '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
