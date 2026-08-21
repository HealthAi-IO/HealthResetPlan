import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_repository.dart';
import '../../core/data/health_models.dart';
import '../../core/di/service_locator.dart';
import '../../core/notification/reminder_scheduler.dart';
import '../../core/widgets/health_ui.dart';
import '../../core/widgets/numeric_picker_field.dart';
import 'quit_smoking_models.dart';
import 'quit_smoking_history_pages.dart';
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
    var profile = await _repository.loadProfile();
    var events = await _repository.loadEvents();
    if (profile != null) {
      events = await _normalizeCheckIns(profile, events);
      profile = await _repository.evaluateAdaptivePlan(
        profile: profile,
        events: events,
        now: DateTime.now(),
      );
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _events = events;
      _loading = false;
    });
  }

  Future<List<QuitSmokingEvent>> _normalizeCheckIns(
    QuitSmokingProfile profile,
    List<QuitSmokingEvent> events,
  ) async {
    final today = DateTime.now();
    final normalized = [...events];
    for (var index = 0; index < normalized.length; index++) {
      final checkIn = normalized[index];
      if (checkIn.type != QuitSmokingEventType.checkIn) continue;
      final time = DateTime.fromMillisecondsSinceEpoch(checkIn.occurredAt);
      final sameDayAsToday = time.year == today.year &&
          time.month == today.month &&
          time.day == today.day;
      if (sameDayAsToday &&
          shouldInvalidateCheckIn(checkIn: checkIn, events: events)) {
        await _repository.deleteEvent(checkIn);
        normalized.removeAt(index);
        index--;
        continue;
      }
      final target = checkIn.cigarettes;
      final smoked = events.where((event) {
        if (event.type != QuitSmokingEventType.smoked) return false;
        final eventTime = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
        return eventTime.year == time.year &&
            eventTime.month == time.month &&
            eventTime.day == time.day;
      }).fold<int>(0, (sum, event) => sum + event.cigarettes);
      final success =
          sameDayAsToday || profile.mode == QuitSmokingMode.immediate
              ? smoked <= target
              : checkIn.success ?? smoked <= target;
      if (checkIn.cigarettes == target && checkIn.success == success) continue;
      final updated = checkIn.copyWith(cigarettes: target, success: success);
      await _repository.updateEvent(updated);
      normalized[index] = updated;
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_profile == null) {
      return _SetupView(onSaved: _load);
    }
    final profile = _profile!;
    final cravings =
        _events.where((event) => event.type == QuitSmokingEventType.craving);
    final progress = calculateQuitSmokingProgress(
      profile: profile,
      events: _events,
      now: _now,
    );
    final successCravings =
        cravings.where((event) => event.success == true).length;
    final hasSmokingRecord = _events.any((event) =>
        event.type == QuitSmokingEventType.smoked &&
        event.occurredAt >= progress.startedAt.millisecondsSinceEpoch);
    final todayCheckIn = _events.where((event) {
      if (event.type != QuitSmokingEventType.checkIn) return false;
      final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
      return time.year == _now.year &&
          time.month == _now.month &&
          time.day == _now.day;
    }).firstOrNull;
    final checkedInToday = todayCheckIn != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('戒烟计划'),
        actions: [
          IconButton(
            tooltip: '戒烟日历',
            onPressed: _openCalendar,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: '调整计划',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) =>
                        _SetupView(profile: profile, onSaved: _load)),
              );
            },
            icon: const Icon(Icons.tune_outlined),
          ),
        ],
      ),
      body: HealthResponsiveContent(
        maxWidth: 960,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _SummaryPanel(
                progress: progress,
                todayCount: progress.todayCount,
                target: quitSmokingTargetForDay(
                  profile: profile,
                  events: _events,
                  day: _now,
                ),
                checkedInToday: checkedInToday,
                achievedToday: todayCheckIn?.success,
                successfulCravings: successCravings,
                hasSmokingRecord: hasSmokingRecord,
                onCheckIn: _checkIn,
              ),
              const SizedBox(height: 12),
              if (profile.mode == QuitSmokingMode.gradual) ...[
                _GradualPlanPanel(
                  profile: profile,
                  now: _now,
                  onContinueStage: _continueCurrentStage,
                  onReplan: _openReplan,
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _recordCraving(),
                      icon: const Icon(Icons.self_improvement_outlined),
                      label: const Text('烟瘾来了'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _recordSmoked(),
                      icon: const Icon(Icons.smoke_free),
                      label: const Text('记录已吸烟'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SavingsBreakdownPanel(
                profile: profile,
                progress: progress,
              ),
              const SizedBox(height: 12),
              _SevenDayTrack(
                profile: profile,
                events: _events,
                now: _now,
                onDayTap: _openDay,
                onCalendarTap: _openCalendar,
              ),
              const SizedBox(height: 12),
              _AdvicePanel(),
              const SizedBox(height: 12),
              const _TodayGuidePanel(),
              const SizedBox(height: 12),
              _HealthMilestonesPanel(
                elapsed: _now.isBefore(progress.smokeFreeStartedAt)
                    ? Duration.zero
                    : _now.difference(progress.smokeFreeStartedAt),
              ),
              const SizedBox(height: 12),
              _StatsPanel(
                events: _events,
                baseline: profile.dailyBaseline,
                cravingSuccessRate:
                    cravings.isEmpty ? 0 : successCravings / cravings.length,
                onTrendTap: _openTrend,
              ),
              const SizedBox(height: 12),
              _RecentEvents(
                events: _events.take(12).toList(),
                onTap: _openEvent,
              ),
            ],
          ),
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
    final event = await _repository.addEvent(
      type: QuitSmokingEventType.smoked,
      cigarettes: result.cigarettes,
      intensity: result.intensity,
      success: null,
      trigger: result.trigger,
      strategy: '',
      note: result.note,
    );
    final invalidated = await _repository.invalidateCheckInForDay(_now);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(invalidated == null
            ? '已记录 ${result.cigarettes} 支'
            : '已记录 ${result.cigarettes} 支，今日需要重新总结'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await _repository.deleteEvent(event);
            if (invalidated != null) {
              await _repository.addEvent(
                type: invalidated.type,
                occurredAt: DateTime.fromMillisecondsSinceEpoch(
                  invalidated.occurredAt,
                ),
                cigarettes: invalidated.cigarettes,
                intensity: invalidated.intensity,
                success: invalidated.success,
                trigger: invalidated.trigger,
                strategy: invalidated.strategy,
                note: invalidated.note,
              );
            }
            await _load();
          },
        ),
      ),
    );
  }

  Future<void> _recordCraving() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CravingCopingDialog(),
    );
    if (result == null) return;
    await _repository.addEvent(
      type: QuitSmokingEventType.craving,
      cigarettes: 0,
      intensity: 3,
      success: result,
      trigger: '',
      strategy: '90 秒应对',
      note: '',
    );
    if (!result && mounted) await _recordSmoked();
    await _load();
    if (result && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('成功应对 +1，累计节省按真实少吸数量计算'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _checkIn() async {
    final alreadyChecked = _events.any((event) {
      if (event.type != QuitSmokingEventType.checkIn) return false;
      final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
      return time.year == _now.year &&
          time.month == _now.month &&
          time.day == _now.day;
    });
    if (alreadyChecked) {
      await _openDay(_now);
      return;
    }
    final profile = _profile!;
    final target = quitSmokingTargetForDay(
      profile: profile,
      events: _events,
      day: _now,
    );
    final todayCount = calculateQuitSmokingProgress(
      profile: profile,
      events: _events,
      now: _now,
    ).todayCount;
    final achieved = todayCount <= target;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('总结今天'),
        content: Text(
          '今天已记录 $todayCount 支，目标不超过 $target 支。系统将标记为${achieved ? '已达标' : '未达标'}。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续记录'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认总结'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.addEvent(
      type: QuitSmokingEventType.checkIn,
      cigarettes: target,
      intensity: 0,
      success: achieved,
      trigger: '',
      strategy: '',
      note: '',
    );
    await _load();
    if (!mounted || _profile == null) return;
    final progress = calculateQuitSmokingProgress(
      profile: _profile!,
      events: _events,
      now: _now,
    );
    final streak = calculateCheckInStreak(events: _events, through: _now);
    await _showCheckInResult(progress, streak, achieved);
  }

  Future<void> _continueCurrentStage() async {
    final profile = _profile;
    if (profile == null) return;
    await _repository.continueCurrentStage(profile: profile, now: _now);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前阶段已延长 3 天，目标支数保持不变')),
    );
  }

  Future<void> _openReplan() async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _SetupView(
          profile: profile,
          onSaved: _load,
          forceRestart: true,
        ),
      ),
    );
  }

  Future<void> _openCalendar() async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuitSmokingCalendarPage(
          profile: profile,
          repository: _repository,
          events: _events,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openDay(DateTime day) async {
    final profile = _profile;
    if (profile == null) return;
    final dayEvents = _events.where((event) {
      final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
      return time.year == day.year &&
          time.month == day.month &&
          time.day == day.day;
    }).toList();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuitSmokingDayDetailPage(
          day: DateTime(day.year, day.month, day.day),
          profile: profile,
          repository: _repository,
          events: dayEvents,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openTrend() async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuitSmokingTrendPage(
          profile: profile,
          events: _events,
        ),
      ),
    );
  }

  Future<void> _openEvent(QuitSmokingEvent event) async {
    final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
    final hasOtherCheckIn = _events.any((item) {
      if (item.id == event.id || item.type != QuitSmokingEventType.checkIn) {
        return false;
      }
      final itemTime = DateTime.fromMillisecondsSinceEpoch(item.occurredAt);
      return itemTime.year == time.year &&
          itemTime.month == time.month &&
          itemTime.day == time.day;
    });
    final changed = await showQuitSmokingEventEditor(
      context: context,
      repository: _repository,
      day: DateTime(time.year, time.month, time.day),
      event: event,
      hasCheckIn: hasOtherCheckIn,
    );
    if (changed) {
      await _load();
    }
  }

  Future<void> _showCheckInResult(
      QuitSmokingProgress progress, int streak, bool achieved) async {
    final reclaimedMinutes = progress.avoidedCigarettes * 5;
    final milestone = _checkInMilestone(streak);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: .65, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (_, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: Icon(
                  achieved ? Icons.check_circle : Icons.flag_outlined,
                  size: 72,
                  color: achieved ? Colors.teal : Colors.orange,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                achieved ? '今日目标已达成' : '今天未达到目标',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(achieved ? '已连续达标 $streak 天' : '记录真实情况就是继续改变的第一步'),
              if (milestone != null) ...[
                const SizedBox(height: 8),
                Text(milestone,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.teal)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                        label: '今日少吸',
                        value:
                            '${(_profile!.dailyBaseline - progress.todayCount).clamp(0, _profile!.dailyBaseline)} 支'),
                  ),
                  Expanded(
                    child: _Metric(
                        label: '今日节省',
                        value:
                            '¥${progress.todaySavedMoney.toStringAsFixed(2)}'),
                  ),
                  Expanded(
                    child: _Metric(
                        label: '少花时间',
                        value:
                            '${reclaimedMinutes ~/ 60}时${reclaimedMinutes % 60}分'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('时间按每少吸一支约节省 5 分钟估算。',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupView extends StatefulWidget {
  const _SetupView({
    this.profile,
    required this.onSaved,
    this.forceRestart = false,
  });

  final QuitSmokingProfile? profile;
  final Future<void> Function() onSaved;
  final bool forceRestart;

  @override
  State<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<_SetupView> {
  final _baseline = TextEditingController();
  final _packCigarettes = TextEditingController(text: '20');
  final _packPrice = TextEditingController();
  final _smokingYears = TextEditingController();
  final _motivation = TextEditingController();
  final _triggers = TextEditingController();
  QuitSmokingMode _mode = QuitSmokingMode.immediate;
  DateTime _targetDate = DateTime.now();
  int _planDurationDays = 14;
  bool _remindersEnabled = false;

  @override
  void initState() {
    super.initState();
    _baseline.addListener(_refreshPreview);
    final profile = widget.profile;
    if (profile == null) return;
    _mode = profile.mode;
    _baseline.text = '${profile.dailyBaseline}';
    _packCigarettes.text = '${profile.packCigarettes}';
    _packPrice.text = '${profile.packPrice}';
    _smokingYears.text = '${profile.smokingYears}';
    _motivation.text = profile.motivation;
    _triggers.text = profile.triggers.join('、');
    _targetDate = DateTime.fromMillisecondsSinceEpoch(profile.targetDate);
    _planDurationDays =
        profile.planDurationDays > 0 ? profile.planDurationDays : 14;
    _remindersEnabled = profile.remindersEnabled;
  }

  @override
  void dispose() {
    _baseline.removeListener(_refreshPreview);
    for (final controller in [
      _baseline,
      _packCigarettes,
      _packPrice,
      _smokingYears,
      _motivation,
      _triggers
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final embedded = widget.profile != null;
    final parsedBaseline = int.tryParse(_baseline.text.trim()) ?? 0;
    final baseline = parsedBaseline > 0
        ? parsedBaseline
        : widget.profile?.dailyBaseline ?? 10;
    final planStartTarget = _planStartTarget(baseline);
    final planStart = _planStartDate;
    final planEnd = planStart.add(Duration(days: _planDurationDays - 1));
    final previewTargets = gradualTargetsFor(
      startTarget: planStartTarget,
      durationDays: _planDurationDays,
    );
    return Scaffold(
      appBar: embedded
          ? AppBar(
              title: Text(widget.forceRestart ? '重新规划' : '调整戒烟计划'),
            )
          : null,
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
              ButtonSegment(
                  value: QuitSmokingMode.immediate, label: Text('立即戒烟')),
              ButtonSegment(
                  value: QuitSmokingMode.gradual, label: Text('逐步减少')),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
          const SizedBox(height: 16),
          _numberField(_baseline, '平均每天吸烟',
              unit: '支', max: 200, initialValue: 10),
          _numberField(_packCigarettes, '每包支数',
              unit: '支', max: 100, initialValue: 20),
          _numberField(_packPrice, '每包价格',
              unit: '元', max: 1000, initialValue: 25),
          _numberField(_smokingYears, '吸烟年限（可选）',
              unit: '年', min: 0, max: 100, initialValue: 10, optional: true),
          if (_mode == QuitSmokingMode.gradual) ...[
            Text('自动减量周期', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 天')),
                ButtonSegment(value: 14, label: Text('14 天')),
                ButtonSegment(value: 28, label: Text('28 天')),
              ],
              selected: {_planDurationDays},
              onSelectionChanged: (value) =>
                  setState(() => _planDurationDays = value.first),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '预计 ${_dateText(planStart)} 开始，${_dateText(planEnd)} 降至 0 支',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text('${previewTargets.join(' → ')} → 0 支'),
                  const SizedBox(height: 4),
                  const Text('连续两天未达标时，当前阶段自动延长 3 天。'),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _motivation,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: '戒烟动机（可选）', hintText: '例如：改善体力、陪伴家人'),
          ),
          TextField(
            controller: _triggers,
            decoration: const InputDecoration(
              labelText: '常见诱因（可选）',
              hintText: '例如：饭后、压力、社交，用顿号分隔',
            ),
          ),
          const SizedBox(height: 12),
          if (_mode == QuitSmokingMode.immediate)
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
          FilledButton(
            onPressed: _save,
            child: Text(widget.forceRestart ? '生成新计划' : '保存戒烟计划'),
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    required String unit,
    double min = 1,
    required double max,
    required double initialValue,
    bool optional = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NumericPickerField(
        controller: controller,
        label: label,
        unit: unit,
        min: min,
        max: max,
        step: 1,
        initialValue: initialValue,
        optional: optional,
      ),
    );
  }

  Future<void> _pickTargetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _targetDate.isBefore(DateTime.now()) ? DateTime.now() : _targetDate,
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
    final restartPlan = _shouldRestartPlan;
    final planStartTarget = _planStartTarget(baseline);
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
      stageGoal: _mode == QuitSmokingMode.gradual ? planStartTarget : 0,
      stageStartDate: _planStartDate,
      remindersEnabled: _remindersEnabled,
      planDurationDays: _planDurationDays,
      planStartTarget: planStartTarget,
      restartPlan: restartPlan,
    );
    await _syncReminder(_remindersEnabled);
    await widget.onSaved();
    if (mounted && widget.profile != null) Navigator.of(context).pop();
  }

  bool get _shouldRestartPlan {
    final profile = widget.profile;
    return widget.forceRestart ||
        profile == null ||
        profile.mode != _mode ||
        (_mode == QuitSmokingMode.gradual &&
            profile.planDurationDays != _planDurationDays);
  }

  DateTime get _planStartDate {
    final today = DateTime.now();
    if (widget.profile == null) {
      return DateTime(today.year, today.month, today.day);
    }
    if (_shouldRestartPlan) {
      final tomorrow = today.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    }
    final profile = widget.profile!;
    return DateTime.fromMillisecondsSinceEpoch(
      profile.planStartDate > 0
          ? profile.planStartDate
          : profile.stageStartDate,
    );
  }

  int _planStartTarget(int baseline) {
    final profile = widget.profile;
    if (profile == null || profile.mode != QuitSmokingMode.gradual) {
      return baseline.clamp(1, baseline).toInt();
    }
    if (!_shouldRestartPlan) {
      return profile.planStartTarget > 0 ? profile.planStartTarget : baseline;
    }
    final currentTarget =
        buildGradualQuitPlan(profile).stageFor(DateTime.now()).target;
    return (currentTarget > 0 ? currentTarget : baseline)
        .clamp(1, baseline)
        .toInt();
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
    required this.achievedToday,
    required this.successfulCravings,
    required this.hasSmokingRecord,
    required this.onCheckIn,
  });

  final QuitSmokingProgress progress;
  final int todayCount;
  final int target;
  final bool checkedInToday;
  final bool? achievedToday;
  final int successfulCravings;
  final bool hasSmokingRecord;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final statusColor = !checkedInToday
        ? Theme.of(context).colorScheme.primary
        : achievedToday == true
            ? AppTheme.success(context)
            : AppTheme.warning(context);
    final statusIcon = !checkedInToday
        ? Icons.schedule_outlined
        : achievedToday == true
            ? Icons.check_circle_outline
            : Icons.error_outline;
    final statusText = !checkedInToday
        ? '今日进行中：已记录 $todayCount 支，目标不超过 $target 支'
        : achievedToday == true
            ? '今日已达标：$todayCount 支，不超过目标 $target 支'
            : '今日未达标：$todayCount 支，目标不超过 $target 支';
    final elapsed = DateTime.now().isBefore(progress.smokeFreeStartedAt)
        ? Duration.zero
        : DateTime.now().difference(progress.smokeFreeStartedAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusText,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasSmokingRecord ? '距离上次吸烟' : '连续未吸烟',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              _durationText(elapsed),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: '今日记录',
                    value: '$todayCount 支',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '累计少吸',
                    value:
                        '${progress.avoidedCigarettesExact.toStringAsFixed(1)} 支',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '成功应对',
                    value: '$successfulCravings 次',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '今日目标不超过 $target 支',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCheckIn,
                icon: Icon(
                  checkedInToday
                      ? Icons.edit_note_outlined
                      : Icons.task_alt_outlined,
                  size: 18,
                ),
                label: Text(checkedInToday ? '查看或更正今日记录' : '总结今天'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradualPlanPanel extends StatelessWidget {
  const _GradualPlanPanel({
    required this.profile,
    required this.now,
    required this.onContinueStage,
    required this.onReplan,
  });

  final QuitSmokingProfile profile;
  final DateTime now;
  final VoidCallback onContinueStage;
  final VoidCallback onReplan;

  @override
  Widget build(BuildContext context) {
    final plan = buildGradualQuitPlan(profile);
    final today = DateTime(now.year, now.month, now.day);
    final current = plan.stageFor(today);
    final beforeStart = today.isBefore(plan.stages.first.start);
    final quitStage = current.target == 0;
    final daysRemaining =
        quitStage ? 0 : current.end.difference(today).inDays.clamp(0, 999) + 1;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final extensionDays = profile.extendedStageIndexes.length * 3;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('自动渐进计划',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text('${profile.planDurationDays} 天基础周期'),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: child,
                ),
              ),
              child: Container(
                key: ValueKey(current.index),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      beforeStart
                          ? '计划将于 ${_dateText(plan.stages.first.start)} 开始'
                          : quitStage
                              ? '已进入完全戒烟阶段'
                              : '当前每日目标：不超过 ${current.target} 支',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      beforeStart
                          ? '今天继续按原目标记录，明天开始自动降低。'
                          : quitStage
                              ? '从 ${_dateText(plan.quitDate)} 起，每日目标保持为 0 支。'
                              : '本阶段还剩 $daysRemaining 天；下一阶段会继续降低目标。',
                    ),
                  ],
                ),
              ),
            ),
            if (extensionDays > 0) ...[
              const SizedBox(height: 10),
              Text(
                '计划已根据记录温和延长 $extensionDays 天，当前目标没有提高。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (profile.needsReplan) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('延长阶段后仍连续两天未达标',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text('你可以保持当前目标再尝试 3 天，或者从当前目标重新生成计划。'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: onContinueStage,
                          child: const Text('继续当前阶段'),
                        ),
                        FilledButton(
                          onPressed: onReplan,
                          child: const Text('重新生成计划'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            for (final stage in plan.stages) ...[
              _GradualStageRow(
                stage: stage,
                currentIndex: beforeStart ? -1 : current.index,
                today: today,
              ),
              if (stage != plan.stages.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _GradualStageRow extends StatelessWidget {
  const _GradualStageRow({
    required this.stage,
    required this.currentIndex,
    required this.today,
  });

  final QuitSmokingStage stage;
  final int currentIndex;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final completed = stage.end.isBefore(today);
    final current = stage.index == currentIndex;
    final color = completed
        ? AppTheme.success(context)
        : current
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline;
    final date = stage.target == 0
        ? '${_dateText(stage.start)} 起'
        : '${_dateText(stage.start)}—${_dateText(stage.end)}';
    return Semantics(
      label:
          '${stage.target == 0 ? '完全戒烟' : '每日不超过 ${stage.target} 支'}，$date，${completed ? '已完成' : current ? '当前阶段' : '未开始'}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              completed
                  ? Icons.check_circle
                  : current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
              color: color,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.target == 0
                        ? '完全戒烟 · 0 支'
                        : '每日不超过 ${stage.target} 支',
                    style: TextStyle(
                      color: color,
                      fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(date, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (current) const Text('当前'),
          ],
        ),
      ),
    );
  }
}

class _SavingsBreakdownPanel extends StatelessWidget {
  const _SavingsBreakdownPanel({
    required this.profile,
    required this.progress,
  });

  final QuitSmokingProfile profile;
  final QuitSmokingProgress progress;

  @override
  Widget build(BuildContext context) {
    final perCigarette = profile.packCigarettes <= 0
        ? 0.0
        : profile.packPrice / profile.packCigarettes;
    final elapsed = DateTime.now().isBefore(progress.startedAt)
        ? Duration.zero
        : DateTime.now().difference(progress.startedAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('累计节省', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '¥${progress.savedMoney.toStringAsFixed(2)}',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '金额按计划开始前的吸烟习惯随时间增加，并扣除实际记录。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _SavingsRow(label: '原来每天吸', value: '${profile.dailyBaseline} 支'),
            _SavingsRow(label: '计划已进行', value: _elapsedPlanText(elapsed)),
            _SavingsRow(
              label: '截至现在预计原本会吸',
              value: '${progress.expectedCigarettes.toStringAsFixed(1)} 支',
            ),
            _SavingsRow(
              label: '实际记录',
              value: '${progress.actualCigarettes} 支',
            ),
            _SavingsRow(
              label: '累计少吸',
              value: '${progress.avoidedCigarettesExact.toStringAsFixed(1)} 支',
              emphasized: true,
            ),
            const Divider(height: 28),
            _SavingsRow(
              label: '每支价格',
              value: '¥${perCigarette.toStringAsFixed(2)}',
            ),
            Text(
              '每包 ¥${profile.packPrice.toStringAsFixed(2)} ÷ ${profile.packCigarettes} 支',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('成功应对烟瘾单独计次，不直接折算成一支烟或增加节省金额。'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SavingsRow extends StatelessWidget {
  const _SavingsRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 16),
            Text(
              value,
              textAlign: TextAlign.end,
              style: emphasized
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null,
            ),
          ],
        ),
      );
}

class _TodayGuidePanel extends StatelessWidget {
  const _TodayGuidePanel();

  @override
  Widget build(BuildContext context) => const Card(
        child: ExpansionTile(
          leading: Icon(Icons.help_outline),
          title: Text('如何使用戒烟计划'),
          subtitle: Text('查看记录、应对烟瘾和每日总结的方法'),
          childrenPadding: EdgeInsets.fromLTRB(18, 0, 18, 18),
          children: [
            _GuideStep(
              icon: Icons.self_improvement_outlined,
              text: '烟瘾出现但还没吸烟时，点击“烟瘾来了”获得应对帮助。',
            ),
            SizedBox(height: 10),
            _GuideStep(
              icon: Icons.smoke_free,
              text: '已经吸烟时，点击“记录已吸烟”如实记下支数。',
            ),
            SizedBox(height: 10),
            _GuideStep(
              icon: Icons.task_alt_outlined,
              text: '一天结束时总结；之后若修改吸烟记录，需要重新总结。',
            ),
          ],
        ),
      );
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
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
    required this.onDayTap,
    required this.onCalendarTap,
  });

  final QuitSmokingProfile profile;
  final List<QuitSmokingEvent> events;
  final DateTime now;
  final ValueChanged<DateTime> onDayTap;
  final VoidCallback onCalendarTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final days =
        List.generate(7, (index) => today.subtract(Duration(days: 6 - index)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('最近 7 天',
                        style: Theme.of(context).textTheme.titleMedium)),
                TextButton(onPressed: onCalendarTap, child: const Text('查看日历')),
              ],
            ),
            const SizedBox(height: 4),
            Text('总结后显示当天是否达到吸烟支数目标',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final day in days)
                  _DayStatus(
                    day: day,
                    today: today,
                    checked: _hasCheckIn(day),
                    achieved: _checkInForDay(day)?.success ??
                        _smokedCount(day) <=
                            quitSmokingTargetForDay(
                              profile: profile,
                              events: events,
                              day: day,
                            ),
                    onTap: () => onDayTap(day),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: Colors.teal),
                const SizedBox(width: 4),
                const Text('已达标'),
                const SizedBox(width: 14),
                Icon(Icons.error,
                    size: 16, color: Theme.of(context).colorScheme.tertiary),
                const SizedBox(width: 4),
                const Text('未达标'),
                const SizedBox(width: 14),
                Icon(Icons.circle,
                    size: 8,
                    color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(width: 4),
                const Text('待总结'),
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
        return time.year == day.year &&
            time.month == day.month &&
            time.day == day.day;
      });

  QuitSmokingEvent? _checkInForDay(DateTime day) => events.where((event) {
        if (event.type != QuitSmokingEventType.checkIn) return false;
        final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
        return time.year == day.year &&
            time.month == day.month &&
            time.day == day.day;
      }).firstOrNull;

  int _smokedCount(DateTime day) => events.where((event) {
        if (event.type != QuitSmokingEventType.smoked) return false;
        final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
        return time.year == day.year &&
            time.month == day.month &&
            time.day == day.day;
      }).fold<int>(0, (sum, event) => sum + event.cigarettes);
}

class _DayStatus extends StatelessWidget {
  const _DayStatus(
      {required this.day,
      required this.today,
      required this.checked,
      required this.achieved,
      required this.onTap});

  final DateTime day;
  final DateTime today;
  final bool checked;
  final bool achieved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = checked
        ? (achieved ? Colors.teal : colors.tertiary)
        : colors.outlineVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 40,
        child: Column(
          children: [
            Text(_weekday(day.weekday),
                style: Theme.of(context).textTheme.bodySmall),
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
                checked
                    ? (achieved ? Icons.check : Icons.priority_high)
                    : Icons.circle,
                size: checked ? 20 : 6,
                color: checked ? Colors.white : color,
              ),
            ),
            const SizedBox(height: 5),
            Text('${day.day}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _HealthMilestonesPanel extends StatelessWidget {
  const _HealthMilestonesPanel({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final completed =
        _healthMilestones.where((item) => elapsed >= item.duration).length;
    final next =
        _healthMilestones.where((item) => elapsed < item.duration).firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('健康变化参考',
                        style: Theme.of(context).textTheme.titleMedium)),
                TextButton(
                  onPressed: () => _showMilestones(context, elapsed),
                  child: const Text('查看全部'),
                ),
              ],
            ),
            Text('已完成 $completed / ${_healthMilestones.length} 个时间里程碑'),
            const SizedBox(height: 10),
            LinearProgressIndicator(
                value: completed / _healthMilestones.length),
            const SizedBox(height: 12),
            Text(
              next == null
                  ? '已达到当前全部参考里程碑'
                  : '下一里程碑：${next.timeLabel} · ${next.title}',
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
  const _HealthMilestone(
      this.duration, this.timeLabel, this.title, this.description);

  final Duration duration;
  final String timeLabel;
  final String title;
  final String description;
}

const _healthMilestones = [
  _HealthMilestone(
      Duration(minutes: 20), '约 20 分钟', '身体开始适应无烟状态', '心率与循环开始进入调整阶段。'),
  _HealthMilestone(
      Duration(hours: 12), '约 12 小时', '一氧化碳相关指标进入调整', '身体逐步减少烟草燃烧产物带来的影响。'),
  _HealthMilestone(
      Duration(days: 2), '约 48 小时', '感官进入恢复阶段', '部分人的嗅觉和味觉可能逐渐改善。'),
  _HealthMilestone(
      Duration(days: 14), '约 2 周', '循环与呼吸持续调整', '持续戒烟有助于循环和肺功能逐步改善。'),
  _HealthMilestone(
      Duration(days: 90), '约 3 个月', '稳定维持阶段', '长期坚持有助于巩固无烟习惯和身体适应。'),
  _HealthMilestone(
      Duration(days: 365), '约 1 年', '长期健康获益阶段', '与吸烟相关的健康风险会随持续戒烟逐步下降。'),
];

class _StatsPanel extends StatelessWidget {
  const _StatsPanel(
      {required this.events,
      required this.baseline,
      required this.cravingSuccessRate,
      required this.onTrendTap});
  final List<QuitSmokingEvent> events;
  final int baseline;
  final double cravingSuccessRate;
  final VoidCallback onTrendTap;
  @override
  Widget build(BuildContext context) {
    final smoked =
        events.where((event) => event.type == QuitSmokingEventType.smoked);
    final last7 = DateTime.now().subtract(const Duration(days: 7));
    final count = smoked
        .where((event) => event.occurredAt >= last7.millisecondsSinceEpoch)
        .fold<int>(0, (sum, event) => sum + event.cigarettes);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('近 7 天'),
                TextButton(onPressed: onTrendTap, child: const Text('趋势'))
              ]),
              Text('共记录 $count 支，基线约 ${baseline * 7} 支'),
              const SizedBox(height: 8),
              Text('渴望成功应对率 ${(cravingSuccessRate * 100).toStringAsFixed(0)}%'),
            ])));
  }
}

class _RecentEvents extends StatelessWidget {
  const _RecentEvents({required this.events, required this.onTap});
  final List<QuitSmokingEvent> events;
  final ValueChanged<QuitSmokingEvent> onTap;
  @override
  Widget build(BuildContext context) => Card(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Text('最近记录', style: TextStyle(fontWeight: FontWeight.w700))),
        if (events.isEmpty)
          const Padding(padding: EdgeInsets.all(18), child: Text('还没有记录。')),
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
              QuitSmokingEventType.craving =>
                event.success == true ? '成功应对渴望' : '记录一次渴望',
              QuitSmokingEventType.checkIn =>
                event.success == true ? '今日戒烟已达标' : '今日戒烟未达标',
            }),
            subtitle: Text(
                '${_dateText(DateTime.fromMillisecondsSinceEpoch(event.occurredAt))}${event.trigger.isEmpty ? '' : ' · ${event.trigger}'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onTap(event),
          ),
      ]));
}

class _EventInput {
  const _EventInput(
      {required this.cigarettes,
      required this.intensity,
      required this.trigger,
      required this.note});
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
  final _formKey = GlobalKey<FormState>();
  final cigarettes = TextEditingController(text: '1');
  final trigger = TextEditingController();
  final note = TextEditingController();
  int intensity = 0;
  @override
  void dispose() {
    cigarettes.dispose();
    trigger.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('记录一次吸烟'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                NumericPickerField(
                    controller: cigarettes,
                    label: '支数',
                    unit: '支',
                    min: 1,
                    max: 100,
                    step: 1,
                    initialValue: 1,
                    validator: (value) {
                      final count = int.tryParse(value?.trim() ?? '');
                      if (count == null || count < 1 || count > 100) {
                        return '请输入 1 至 100 支';
                      }
                      return null;
                    }),
                TextField(
                    controller: trigger,
                    decoration: const InputDecoration(labelText: '诱因（可选）')),
                TextField(
                    controller: note,
                    decoration: const InputDecoration(labelText: '备注（可选）')),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.pop(
                      context,
                      _EventInput(
                          cigarettes: int.parse(cigarettes.text.trim()),
                          intensity: intensity,
                          trigger: trigger.text.trim(),
                          note: note.text.trim()));
                },
                child: const Text('保存'))
          ]);
}

class _CravingCopingDialog extends StatefulWidget {
  const _CravingCopingDialog();
  @override
  State<_CravingCopingDialog> createState() => _CravingCopingDialogState();
}

class _CravingCopingDialogState extends State<_CravingCopingDialog> {
  static const _totalSeconds = 90;
  int _remaining = _totalSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _remaining == 0) return;
      setState(() => _remaining--);
      if (_remaining == 0) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _guidance => switch (_remaining) {
        > 65 => '慢慢吸气 4 秒，再呼气 6 秒',
        > 40 => '喝几口水，让注意力离开烟',
        > 15 => '站起来走动，离开当前触发环境',
        _ => '再坚持片刻，这次渴望正在减弱',
      };

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('先挺过这 90 秒'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 112,
                height: 112,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                    value: _remaining / _totalSeconds,
                    strokeWidth: 8,
                  ),
                  Text(
                    '$_remaining',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              Text(_guidance, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _remaining = 0),
                child: const Text('提前结束'),
              ),
            ]),
          ),
          actions: _remaining > 0
              ? null
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('还是吸烟了'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('已经挺过去'),
                  ),
                ],
        ),
      );
}

String _durationText(Duration value) {
  final duration = value.isNegative ? Duration.zero : value;
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24).toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$days 天  $hours:$minutes:$seconds';
}

String _elapsedPlanText(Duration value) {
  final duration = value.isNegative ? Duration.zero : value;
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  return '$days 天 $hours 小时';
}

String? _checkInMilestone(int streak) => switch (streak) {
      3 => '连续达标 3 天',
      7 => '连续达标一周',
      14 => '连续达标两周',
      30 => '连续达标一个月',
      90 => '连续达标三个月',
      180 => '连续达标半年',
      365 => '连续达标一年',
      _ => null,
    };

String _weekday(int value) =>
    const ['一', '二', '三', '四', '五', '六', '日'][value - 1];

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
                  elapsed >= item.duration
                      ? Icons.check_circle
                      : Icons.schedule_outlined,
                  color: elapsed >= item.duration ? Colors.teal : null,
                ),
                title: Text('${item.timeLabel} · ${item.title}'),
                subtitle: Text(item.description),
              ),
            const Divider(),
            Text('内容参考：世界卫生组织及公共卫生机构戒烟健康资料。',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

String _dateText(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
