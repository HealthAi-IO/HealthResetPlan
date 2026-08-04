import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../meals/meal_input_args.dart';
import '../meals/macro_ring.dart';

const _welcomeLetterParagraphs = [
  '也许你曾经拥有更好的体力、更规律的作息，或者一个让自己更满意的身体状态。',
  '后来，因为工作、压力、熬夜、饮食失控，或生活中接连不断的事情，你渐渐忽略了身体。等到疲惫、体重变化或健康指标开始提醒你时，你才发现，自己已经离理想的状态有些远了。',
  '但现在开始，一点也不晚。',
  '找回健康，不需要突然改变全部生活，也不需要依靠几天的拼命坚持。真正有效的改变，往往从一件很小、但可以持续完成的事情开始。',
  '今天，你可以认真记录一次体重或血压，可以为自己选择一顿更合适的饭，可以完成十分钟运动，也可以比平时早一点放下手机、准备休息。',
  '这些行动不会立刻改变一切，但它们会留下真实的记录。记录会形成趋势，趋势会帮助你看清问题，而看清之后，你才能做出更适合自己的调整。',
  '健康重启计划存在的意义，就是陪你完成这个过程：帮你记录身体的真实变化，提醒你完成今天的小目标，让每一份坚持都能被看见，也让每一次调整都有依据。',
  '你不需要和别人比较，也不必因为一次中断而否定之前的努力。健康从来不是一场只能向前、不能停下的比赛。',
  '如果昨天没有做好，那就从今天重新开始；如果今天只能完成一件事，那就认真完成这一件事。',
  '请相信，身体会记住你为它付出的每一次努力。',
  '从现在开始，迈出今天这一步。',
];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _profilePromptDismissedKey = 'home_profile_prompt_dismissed_v1';
  static const _indicatorPromptSnoozedUntilKey =
      'home_indicator_prompt_snoozed_until_v2';
  final HealthRepository _repo = sl<HealthRepository>();

  HealthDashboardData? _data;
  List<HealthIndicatorEntry> _recentIndicators = const [];
  List<MealRecordData> _mealRecords = const [];
  List<MealRecordData> _todayMealRecords = const [];
  List<HealthReportRecord> _recentReports = const [];
  DateTime _selectedMealDate = DateTime.now();
  bool _loading = true;
  bool _promptOpen = false;
  bool _entryPromptsRunning = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    final cutoff = DateTime.now().subtract(const Duration(days: 3));
    final results = await Future.wait<Object?>([
      _repo.loadDashboard(),
      _repo.loadIndicatorsSince(cutoff),
      _repo.loadMealsForDate(_selectedMealDate),
      _repo.loadReportRecords(limit: 3),
      _repo.loadMealsForDate(DateTime.now()),
    ]);
    if (!mounted) return;
    setState(() {
      _data = results[0] as HealthDashboardData;
      _recentIndicators = results[1] as List<HealthIndicatorEntry>;
      _mealRecords = results[2] as List<MealRecordData>;
      _recentReports = results[3] as List<HealthReportRecord>;
      _todayMealRecords = results[4] as List<MealRecordData>;
      _loading = false;
    });
    _runEntryPrompts(results[0] as HealthDashboardData);
  }

  Future<void> _runEntryPrompts(HealthDashboardData data) async {
    if (_entryPromptsRunning) return;
    _entryPromptsRunning = true;
    try {
      await _maybeShowWelcomeLetter();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await _maybeShowNextPrompt(data);
    } finally {
      _entryPromptsRunning = false;
    }
  }

  Future<void> _maybeShowWelcomeLetter() async {
    if (!mounted || _promptOpen) return;
    final userId = UserSession.instance.userId;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(UserSession.welcomeLetterPendingUserKey) != userId) {
      return;
    }
    await prefs.remove(UserSession.welcomeLetterPendingUserKey);
    if (!mounted) return;
    _promptOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) await _openWelcomeLetter();
    _promptOpen = false;
  }

  Future<void> _maybeShowNextPrompt(HealthDashboardData data) async {
    if (!mounted || _promptOpen) return;

    final prompt = _nextPrompt(data);
    if (prompt == null) return;
    final prefs = await SharedPreferences.getInstance();
    final isIndicatorPrompt =
        prompt.confirmAction == _HomePromptAction.indicator;
    if (isIndicatorPrompt) {
      final snoozedUntil = prefs.getInt(_indicatorPromptSnoozedUntilKey) ?? 0;
      if (snoozedUntil > DateTime.now().millisecondsSinceEpoch) return;
    } else if (prefs.getBool(prompt.dismissedKey) == true) {
      return;
    }
    if (!mounted) return;

    _promptOpen = true;
    final action = await showDialog<_HomePromptAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(prompt.title),
        content: Text(prompt.content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _HomePromptAction.later),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _HomePromptAction.dismiss),
            child: Text(isIndicatorPrompt ? '3 天内不再提醒' : '不再提醒'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, prompt.confirmAction),
            child: Text(prompt.confirmText),
          ),
        ],
      ),
    );
    _promptOpen = false;
    if (!mounted) return;

    if (action == _HomePromptAction.dismiss) {
      if (isIndicatorPrompt) {
        await prefs.setInt(
          _indicatorPromptSnoozedUntilKey,
          DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch,
        );
      } else {
        await prefs.setBool(prompt.dismissedKey, true);
      }
    } else if (action == _HomePromptAction.profile) {
      context.go('/profile?guideProfile=1');
    } else if (action == _HomePromptAction.indicator) {
      context.push('/indicators/input').then((_) {
        if (mounted) _load(silent: true);
      });
    }
  }

  _HomePrompt? _nextPrompt(HealthDashboardData data) {
    final profile = data.profile;
    if (profile == null || !profile.isComplete) {
      return const _HomePrompt(
        dismissedKey: _profilePromptDismissedKey,
        title: '先填写你的健康数据',
        content: '当前还没有完整健康档案。完善档案后，系统会基于你的年龄、身高、体重和目标生成更准确的建议。',
        confirmText: '去填写',
        confirmAction: _HomePromptAction.profile,
      );
    }
    if (_shouldPromptForIndicator(data)) {
      return const _HomePrompt(
        dismissedKey: _indicatorPromptSnoozedUntilKey,
        title: '记录一下最近的健康状态',
        content: '你已经连续 3 天没有记录健康指标了。记录体重、血压或血糖，趋势和计划建议会更准确。',
        confirmText: '去录入',
        confirmAction: _HomePromptAction.indicator,
      );
    }
    return null;
  }

  bool _shouldPromptForIndicator(HealthDashboardData data) {
    if (_recentIndicators.isNotEmpty) return false;
    final profileUpdatedAt = data.profile?.updatedAt ?? 0;
    if (profileUpdatedAt <= 0) return false;
    return DateTime.now().difference(
            DateTime.fromMillisecondsSinceEpoch(profileUpdatedAt)) >=
        const Duration(days: 3);
  }

  void _selectMealDate(DateTime date) {
    setState(() => _selectedMealDate = date);
    _load(silent: true);
  }

  void _openMealInput(String mealType) {
    context
        .push(
      '/meals/input',
      extra: MealInputArgs(
        mealType: mealType,
        eatenDate: _selectedMealDate,
      ),
    )
        .then((_) {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _openMealCalendar() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => _MealCalendarDialog(
        selectedDate: _selectedMealDate,
        records: _mealRecords,
        onPickDate: () => showDatePicker(
          context: ctx,
          initialDate: _selectedMealDate,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 30)),
          locale: const Locale('zh', 'CN'),
        ),
      ),
    );
    if (picked != null) _selectMealDate(picked);
  }

  Future<void> _openWelcomeLetter() async {
    void startProfile(BuildContext overlayContext) {
      Navigator.pop(overlayContext);
      context.go('/profile?guideProfile=1');
    }

    if (MediaQuery.sizeOf(context).width >= 700) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: SizedBox(
            width: 620,
            height: min(MediaQuery.sizeOf(dialogContext).height * 0.86, 760),
            child: _WelcomeLetterEntrance(
              child: _WelcomeLetterContent(
                onStart: () => startProfile(dialogContext),
                onLater: () => Navigator.pop(dialogContext),
              ),
            ),
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _WelcomeLetterEntrance(
          child: _WelcomeLetterContent(
            onStart: () => startProfile(sheetContext),
            onLater: () => Navigator.pop(sheetContext),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const _HomeLoadingView();
    }
    final data = _data;
    final profile = data?.profile;
    final bottomPad = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;
    final now = DateTime.now();
    final todayLabel = DateFormat('MM月dd日 EEEE', 'zh_CN').format(now);

    // 今日计划
    final todayPlans = (data?.plans ?? []).where((p) {
      final d = p.date;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();
    final todayMeal = todayPlans.where((p) => p.type == 'meal').firstOrNull;
    final todayExercise =
        todayPlans.where((p) => p.type == 'exercise').firstOrNull;

    // 今日打卡
    final todayClocks = (data?.clockRecords ?? []).where((r) {
      final t = r.clockTime;
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).toList();
    final doneTypes =
        todayClocks.where((r) => r.status == 'done').map((r) => r.type).toSet();
    final completion = data?.todayCompletion ?? 0;
    final desktop = MediaQuery.sizeOf(context).width >= 1100;

    if (desktop) {
      return _DesktopHomeDashboard(
        data: data,
        reports: _recentReports,
        meals: _todayMealRecords,
        todayPlans: todayPlans,
        todayClocks: todayClocks,
        doneTypes: doneTypes,
        completion: completion,
        todayLabel: todayLabel,
        onRefresh: _load,
        onMealRecord: _openMealInput,
        onOpenPlan: () => context.go('/plan'),
        onOpenClock: () => context.go('/clock'),
        onOpenStats: () => context.go('/stats'),
        onOpenReports: () => context.push('/report'),
        onOpenContent: () => context.push('/content'),
        onOpenLetter: _openWelcomeLetter,
        onAddIndicator: () {
          context.push('/indicators/input').then((_) {
            if (mounted) _load(silent: true);
          });
        },
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const PageStorageKey('home-scroll'),
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
        cacheExtent: 900,
        children: [
          // 顶部仪表盘 Hero
          _DashboardHero(
            profile: profile,
            completion: completion,
            doneTypes: doneTypes,
            todayLabel: todayLabel,
            onClockTap: () => context.go('/clock'),
          ),
          const SizedBox(height: 14),
          _WelcomeLetterCard(onTap: _openWelcomeLetter),
          const SizedBox(height: 14),
          _WeeklyContentCard(onTap: () => context.push('/content')),
          const SizedBox(height: 14),

          _FoodDiaryPanel(
            selectedDate: _selectedMealDate,
            records: _mealRecords,
            targets: DailyNutritionTargets.fromProfile(profile),
            onDateChanged: _selectMealDate,
            onRecord: _openMealInput,
            onOpenCalendar: _openMealCalendar,
            onOpenRecord: (record) {
              final id = record.id;
              if (id == null) return;
              context.push('/meals/detail/$id').then((_) {
                if (mounted) _load(silent: true);
              });
            },
          ),
          const SizedBox(height: 14),

          // 今日关键指标
          _TodayMetricsRow(
              data: data,
              onAddIndicator: () {
                context.push('/indicators/input').then((_) {
                  if (mounted) _load(silent: true);
                });
              }),
          const SizedBox(height: 14),

          // 今日计划摘要
          _TodayPlanCard(
            meal: todayMeal,
            exercise: todayExercise,
            onGenerate: () async {
              try {
                await _repo.generateWeeklyPlan();
                if (!mounted) return;
                ScaffoldMessenger.of(
                        context) // ignore: use_build_context_synchronously
                    .showSnackBar(const SnackBar(content: Text('已生成 7 天本地计划')));
              } on PlanBlockedException catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                        context) // ignore: use_build_context_synchronously
                    .showSnackBar(SnackBar(content: Text(error.message)));
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                        context) // ignore: use_build_context_synchronously
                    .showSnackBar(const SnackBar(content: Text('计划生成失败，请重试')));
              }
            },
            onViewAll: () => context.go('/plan'),
          ),
          const SizedBox(height: 14),

          // 快捷入口
          _Panel(
            title: '快捷入口',
            child: LayoutBuilder(builder: (_, c) {
              final cols = c.maxWidth >= 600 ? 6 : 3;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.95,
                children: [
                  _QuickEntry(
                      icon: Icons.assignment_ind_outlined,
                      label: '健康档案',
                      color: Colors.teal,
                      onTap: () => context.go('/profile')),
                  _QuickEntry(
                      icon: Icons.scale_outlined,
                      label: '录入指标',
                      color: AppTheme.deepBlue,
                      onTap: () {
                        context.push('/indicators/input').then((_) {
                          if (mounted) _load(silent: true);
                        });
                      }),
                  _QuickEntry(
                      icon: Icons.list_alt_outlined,
                      label: '指标历史',
                      color: Colors.indigo,
                      onTap: () {
                        context.push('/indicators').then((_) {
                          if (mounted) _load(silent: true);
                        });
                      }),
                  _QuickEntry(
                      icon: Icons.event_note_outlined,
                      label: '7天计划',
                      color: Colors.green,
                      onTap: () => context.go('/plan')),
                  _QuickEntry(
                      icon: Icons.camera_alt_outlined,
                      label: '拍餐识别',
                      color: Colors.pinkAccent,
                      onTap: () => _openMealInput('lunch')),
                  _QuickEntry(
                      icon: Icons.face_retouching_natural_outlined,
                      label: 'AI 图像分析',
                      color: Colors.purple,
                      onTap: () => context.push('/self-check')),
                  _QuickEntry(
                      icon: Icons.insights_outlined,
                      label: '趋势统计',
                      color: Colors.orange,
                      onTap: () => context.go('/stats')),
                  _QuickEntry(
                      icon: Icons.auto_stories_outlined,
                      label: '健康资讯',
                      color: Colors.cyan.shade700,
                      onTap: () => context.push('/content')),
                ],
              );
            }),
          ),
          const SizedBox(height: 14),

          // 最近指标（近 3 天）
          _RecentIndicatorsPanel(
            indicators: _recentIndicators,
            onAdd: () {
              context.push('/indicators/input').then((_) {
                if (mounted) _load(silent: true);
              });
            },
            onViewAll: () => context.push('/indicators'),
          ),
          const SizedBox(height: 14),

          // 最近打卡 + 提醒规则
          LayoutBuilder(builder: (_, c) {
            final wide = c.maxWidth >= 960;
            final clockPanel = _Panel(
              title: '最近打卡',
              action: TextButton(
                  onPressed: () => context.go('/clock'),
                  child: const Text('全部')),
              child: _RecentClockList(
                  records: todayClocks.isNotEmpty
                      ? todayClocks
                      : (data?.clockRecords ?? [])),
            );
            final reminderPanel = _Panel(
              title: '提醒规则',
              action: TextButton(
                  onPressed: () => context.go('/clock'),
                  child: const Text('管理')),
              child: _ReminderPreview(reminders: data?.reminders ?? []),
            );
            if (wide) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: clockPanel),
                    const SizedBox(width: 12),
                    Expanded(child: reminderPanel),
                  ]);
            }
            return Column(children: [
              clockPanel,
              const SizedBox(height: 12),
              reminderPanel
            ]);
          }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _DesktopHomeDashboard extends StatelessWidget {
  const _DesktopHomeDashboard({
    required this.data,
    required this.reports,
    required this.meals,
    required this.todayPlans,
    required this.todayClocks,
    required this.doneTypes,
    required this.completion,
    required this.todayLabel,
    required this.onRefresh,
    required this.onMealRecord,
    required this.onOpenPlan,
    required this.onOpenClock,
    required this.onOpenStats,
    required this.onOpenReports,
    required this.onOpenContent,
    required this.onOpenLetter,
    required this.onAddIndicator,
  });

  final HealthDashboardData? data;
  final List<HealthReportRecord> reports;
  final List<MealRecordData> meals;
  final List<PlanRecordData> todayPlans;
  final List<ClockRecordData> todayClocks;
  final Set<String> doneTypes;
  final double completion;
  final String todayLabel;
  final Future<void> Function({bool silent}) onRefresh;
  final ValueChanged<String> onMealRecord;
  final VoidCallback onOpenPlan;
  final VoidCallback onOpenClock;
  final VoidCallback onOpenStats;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenContent;
  final VoidCallback onOpenLetter;
  final VoidCallback onAddIndicator;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final profile = data?.profile;
    final weight = data?.latestIndicator('weight');
    final bodyFat = data?.latestIndicator('body_fat');
    final bmi = profile == null || profile.bmi == 0
        ? null
        : profile.bmi.toStringAsFixed(1);
    final trends = data?.weightTrend(limit: 7) ?? const <double>[];
    final mealTypes = meals.map((item) => item.mealType).toSet();
    final now = DateTime.now();
    final weightTime = weight?.measuredTime;
    final weightDone = doneTypes.contains('weight') ||
        (weightTime != null &&
            weightTime.year == now.year &&
            weightTime.month == now.month &&
            weightTime.day == now.day);
    final completed = [
      mealTypes.contains('breakfast'),
      mealTypes.contains('lunch'),
      mealTypes.contains('dinner'),
      doneTypes.contains('exercise'),
      doneTypes.contains('water'),
      weightDone,
    ].where((done) => done).length;
    final taskCompletion = completed / 6;

    return RefreshIndicator(
      onRefresh: () => onRefresh(),
      child: ListView(
        key: const PageStorageKey('desktop-home-scroll'),
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '首页',
                      style:
                          TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(todayLabel,
                        style: const TextStyle(color: AppTheme.muted)),
                  ],
                ),
              ),
              Text(
                '今日完成 $completed 项',
                style: TextStyle(color: primary, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                tooltip: '刷新数据',
                onPressed: () => onRefresh(),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _DesktopBrandBanner(profile: profile, todayLabel: todayLabel),
          const SizedBox(height: 12),
          _WelcomeLetterCard(onTap: onOpenLetter),
          const SizedBox(height: 12),
          _WeeklyContentCard(onTap: onOpenContent),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final gap = constraints.maxWidth >= 1300 ? 14.0 : 10.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 31,
                    child: _DesktopSection(
                      title: '今日计划',
                      trailing: Text(
                        '${(taskCompletion * 100).round()}% 已完成',
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 13),
                      ),
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: taskCompletion,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 14),
                          _DesktopTaskRow(
                            icon: Icons.breakfast_dining_outlined,
                            label: '早餐',
                            detail: _mealPlanDetail(todayPlans, '早餐'),
                            done: mealTypes.contains('breakfast'),
                            onTap: () => onMealRecord('breakfast'),
                          ),
                          _DesktopTaskRow(
                            icon: Icons.lunch_dining_outlined,
                            label: '午餐',
                            detail: _mealPlanDetail(todayPlans, '午餐'),
                            done: mealTypes.contains('lunch'),
                            onTap: () => onMealRecord('lunch'),
                          ),
                          _DesktopTaskRow(
                            icon: Icons.dinner_dining_outlined,
                            label: '晚餐',
                            detail: _mealPlanDetail(todayPlans, '晚餐'),
                            done: mealTypes.contains('dinner'),
                            onTap: () => onMealRecord('dinner'),
                          ),
                          _DesktopTaskRow(
                            icon: Icons.directions_run_outlined,
                            label: '运动计划',
                            detail: _planDetail(todayPlans, 'exercise'),
                            done: doneTypes.contains('exercise'),
                            onTap: onOpenClock,
                          ),
                          _DesktopTaskRow(
                            icon: Icons.water_drop_outlined,
                            label: '饮水目标',
                            detail: '目标 2000 ml',
                            done: doneTypes.contains('water'),
                            onTap: onOpenClock,
                          ),
                          _DesktopTaskRow(
                            icon: Icons.scale_outlined,
                            label: '记录体重',
                            detail: weight?.displayValue ?? '今日尚未记录',
                            done: weightDone,
                            onTap: onAddIndicator,
                            showDivider: false,
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: onOpenPlan,
                              icon: const Icon(Icons.calendar_month_outlined),
                              label: const Text('查看完整计划'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    flex: 36,
                    child: Column(
                      children: [
                        _DesktopSection(
                          title: '健康概览',
                          trailing: TextButton(
                            onPressed: onOpenStats,
                            child: const Text('近 7 日'),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    weight?.displayValue ?? '-- kg',
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    profile?.weightKg == 0
                                        ? '目标未设置'
                                        : '档案体重 ${profile?.weightKg.toStringAsFixed(1)} kg',
                                    style: const TextStyle(
                                      color: AppTheme.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 150,
                                width: double.infinity,
                                child: _WeightTrendChart(values: trends),
                              ),
                              const SizedBox(height: 12),
                              _DesktopMetricRow(
                                icon: Icons.monitor_weight_outlined,
                                label: 'BMI',
                                value: bmi ?? '--',
                              ),
                              _DesktopMetricRow(
                                icon: Icons.accessibility_new_outlined,
                                label: '体脂率',
                                value: bodyFat?.displayValue ?? '--',
                              ),
                              _DesktopMetricRow(
                                icon: Icons.task_alt_outlined,
                                label: '今日打卡',
                                value: '$completed 项',
                                showDivider: false,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DesktopSection(
                          title: '最近健康指标',
                          trailing: TextButton(
                            onPressed: onAddIndicator,
                            child: const Text('录入'),
                          ),
                          child: _DesktopIndicators(
                            indicators:
                                (data?.indicators ?? const []).take(4).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    flex: 28,
                    child: Column(
                      children: [
                        _DesktopSection(
                          title: '快捷操作',
                          child: Column(
                            children: [
                              _DesktopActionRow(
                                icon: Icons.restaurant_outlined,
                                label: '记录饮食',
                                onTap: () => onMealRecord('lunch'),
                              ),
                              _DesktopActionRow(
                                icon: Icons.scale_outlined,
                                label: '记录健康指标',
                                onTap: onAddIndicator,
                              ),
                              _DesktopActionRow(
                                icon: Icons.check_circle_outline,
                                label: '完成今日打卡',
                                onTap: onOpenClock,
                              ),
                              _DesktopActionRow(
                                icon: Icons.event_note_outlined,
                                label: '查看健康计划',
                                onTap: onOpenPlan,
                                showDivider: false,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DesktopSection(
                          title: '最近报告',
                          trailing: TextButton(
                            onPressed: onOpenReports,
                            child: const Text('全部'),
                          ),
                          child: reports.isEmpty
                              ? const _DesktopEmpty(
                                  icon: Icons.description_outlined,
                                  text: '暂无报告记录',
                                )
                              : Column(
                                  children: [
                                    for (var i = 0; i < reports.length; i++)
                                      _DesktopReportRow(
                                        report: reports[i],
                                        showDivider: i < reports.length - 1,
                                        onTap: onOpenReports,
                                      ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 12),
                        _DesktopSection(
                          title: '数据状态',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              UserSession.instance.isAccountLogin
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_off_outlined,
                              color: UserSession.instance.isAccountLogin
                                  ? Colors.green.shade600
                                  : AppTheme.muted,
                            ),
                            title: const Text('账号数据已连接'),
                            subtitle: const Text('修改会自动安全保存'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/profile'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _planDetail(List<PlanRecordData> plans, String type) {
    final plan = plans.where((item) => item.type == type).firstOrNull;
    if (plan == null) return '暂无计划';
    return plan.summary.isEmpty ? plan.label : plan.summary;
  }

  static String _mealPlanDetail(List<PlanRecordData> plans, String meal) {
    final detail = _planDetail(plans, 'meal');
    return detail == '暂无计划' ? '点击记录$meal' : detail;
  }
}

class _DesktopBrandBanner extends StatelessWidget {
  const _DesktopBrandBanner({
    required this.profile,
    required this.todayLabel,
  });

  final UserProfileData? profile;
  final String todayLabel;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final name = (profile?.nickname.isNotEmpty == true)
        ? profile!.nickname
        : UserSession.instance.name;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.accentSoftGradient(context),
          border: Border.all(color: primary.withValues(alpha: 0.16)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(color: primary, child: const SizedBox(width: 4)),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? '健康重启计划' : '你好，$name',
                              style: const TextStyle(
                                color: AppTheme.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '今日进度',
                              style: TextStyle(
                                color: primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              '今天，从一项记录开始',
                              style: TextStyle(
                                color: AppTheme.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              '小小的行动，也会成为看得见的改变。',
                              style: TextStyle(
                                color: AppTheme.muted,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Text(
                        todayLabel,
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeLetterCard extends StatelessWidget {
  const _WelcomeLetterCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colors.primary.withValues(alpha: 0.14),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Icon(Icons.mail_outline),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '写给正在重新出发的你',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '健康不是突然改变，而是在一次次行动中慢慢找回来。',
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '读一读',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.chevron_right, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklyContentCard extends StatelessWidget {
  const _WeeklyContentCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_stories_outlined, color: primary),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '每周健康科普',
                      style: TextStyle(
                        color: AppTheme.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '用轻量卡片了解饮食、运动、睡眠与健康习惯',
                      style: TextStyle(color: AppTheme.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeLetterContent extends StatelessWidget {
  const _WelcomeLetterContent({
    required this.onStart,
    required this.onLater,
  });

  final VoidCallback onStart;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.mail_outline, color: colors.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '写给正在重新出发的你',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: onLater,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const Text('你好！', style: TextStyle(height: 1.75)),
                const SizedBox(height: 14),
                for (final paragraph in _welcomeLetterParagraphs) ...[
                  Text(paragraph, style: const TextStyle(height: 1.75)),
                  const SizedBox(height: 14),
                ],
                Text(
                  '一点一点改变，一步一步，重新找回健康的自己。',
                  style: TextStyle(
                    height: 1.75,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  '健康重启计划团队\n现在出发，重新找回健康的自己！',
                  style: TextStyle(height: 1.7, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(onPressed: onLater, child: const Text('稍后再看')),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onStart,
                  child: const Text('开始我的健康重启'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WelcomeLetterEntrance extends StatelessWidget {
  const _WelcomeLetterEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _DesktopSection extends StatelessWidget {
  const _DesktopSection({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DesktopTaskRow extends StatelessWidget {
  const _DesktopTaskRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.done,
    required this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String detail;
  final bool done;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  done
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank,
                  color: done ? Colors.green.shade600 : AppTheme.cardBorder,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  done ? '已完成' : '去记录',
                  style: TextStyle(
                    color: done ? Colors.green.shade600 : primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

class _DesktopMetricRow extends StatelessWidget {
  const _DesktopMetricRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: primary),
              const SizedBox(width: 10),
              Expanded(child: Text(label)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

class _DesktopActionRow extends StatelessWidget {
  const _DesktopActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(icon, color: primary, size: 21),
          title:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right, size: 19),
          onTap: onTap,
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

class _DesktopIndicators extends StatelessWidget {
  const _DesktopIndicators({required this.indicators});

  final List<HealthIndicatorEntry> indicators;

  @override
  Widget build(BuildContext context) {
    if (indicators.isEmpty) {
      return const _DesktopEmpty(
        icon: Icons.monitor_heart_outlined,
        text: '暂无健康指标',
      );
    }
    return Column(
      children: [
        for (var i = 0; i < indicators.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(indicators[i].label)),
                Text(
                  indicators[i].displayValue,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                Text(
                  DateFormat('MM/dd').format(indicators[i].measuredTime),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (i < indicators.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }
}

class _DesktopReportRow extends StatelessWidget {
  const _DesktopReportRow({
    required this.report,
    required this.showDivider,
    required this.onTap,
  });

  final HealthReportRecord report;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.description_outlined, color: primary),
          title: Text(
            report.summary.isEmpty ? '体检报告' : report.summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${DateFormat('yyyy-MM-dd').format(report.reportDateTime)} · ${report.indicatorCount} 项指标',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, size: 19),
          onTap: onTap,
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

class _DesktopEmpty extends StatelessWidget {
  const _DesktopEmpty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: AppTheme.cardBorder, size: 30),
            const SizedBox(height: 8),
            Text(text,
                style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _WeightTrendChart extends StatelessWidget {
  const _WeightTrendChart({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return const _DesktopEmpty(
        icon: Icons.show_chart,
        text: '记录两次体重后显示趋势',
      );
    }
    return CustomPaint(
      painter: _WeightTrendPainter(
        values: values,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _WeightTrendPainter extends CustomPainter {
  const _WeightTrendPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppTheme.cardBorder.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final minValue = values.reduce(min);
    final maxValue = values.reduce(max);
    final range = max(maxValue - minValue, 1);
    final path = Path();
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final normalized = (values[i] - minValue) / range;
      final y = size.height - 14 - normalized * (size.height - 28);
      final point = Offset(x, y);
      points.add(point);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 4, Paint()..color = color);
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightTrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _HomeLoadingView extends StatelessWidget {
  const _HomeLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _SkeletonBlock(height: 188),
        SizedBox(height: 14),
        _SkeletonBlock(height: 220),
        SizedBox(height: 14),
        _SkeletonBlock(height: 130),
      ],
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
    );
  }
}

class _HomePrompt {
  const _HomePrompt({
    required this.dismissedKey,
    required this.title,
    required this.content,
    required this.confirmText,
    required this.confirmAction,
  });

  final String dismissedKey;
  final String title;
  final String content;
  final String confirmText;
  final _HomePromptAction confirmAction;
}

enum _HomePromptAction { later, dismiss, profile, indicator }

// ── 仪表盘 Hero（进度环 + 今日打卡状态） ────────────────────────
class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.profile,
    required this.completion,
    required this.doneTypes,
    required this.todayLabel,
    required this.onClockTap,
  });

  final UserProfileData? profile;
  final double completion;
  final Set<String> doneTypes;
  final String todayLabel;
  final VoidCallback onClockTap;

  static const _clockItems = [
    ('meal', '饮食', Icons.restaurant_outlined),
    ('exercise', '运动', Icons.directions_run_outlined),
    ('medicine', '用药', Icons.medication_outlined),
    ('weight', '称重', Icons.scale_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
    final name = (profile?.nickname.isNotEmpty == true)
        ? profile!.nickname
        : UserSession.instance.name;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.accentSoftGradient(context),
          border: Border.all(color: primary.withValues(alpha: 0.16)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: primary,
                child: const SizedBox(width: 4),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? '健康重启计划' : '你好，$name',
                                  style: const TextStyle(
                                    color: AppTheme.ink,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  todayLabel,
                                  style: const TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '今日进度',
                                  style: TextStyle(
                                    color: primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  '今天，从一项记录开始',
                                  style: TextStyle(
                                    color: AppTheme.ink,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  '小小的行动，也会成为看得见的改变。',
                                  style: TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 12,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: onClockTap,
                            child: _ProgressRing(
                              value: completion,
                              size: 76,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          for (var index = 0;
                              index < _clockItems.length;
                              index++) ...[
                            Expanded(
                              child: _ClockStatusDot(
                                icon: _clockItems[index].$3,
                                label: _clockItems[index].$2,
                                done: doneTypes.contains(_clockItems[index].$1),
                              ),
                            ),
                            if (index < _clockItems.length - 1)
                              const SizedBox(width: 8),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                          ),
                          onPressed: onClockTap,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '开始记录',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(Icons.arrow_forward, size: 15),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 圆形进度环 ────────────────────────────────────────────────
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.value,
    required this.size,
    required this.color,
  });

  final double value;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(size, size),
          painter: _RingPainter(value: value, color: color),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$pct%',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w900, fontSize: 18)),
          const Text('完成',
              style: TextStyle(color: AppTheme.muted, fontSize: 10)),
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * value,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

// ── 打卡状态点 ────────────────────────────────────────────────
class _ClockStatusDot extends StatelessWidget {
  const _ClockStatusDot({
    required this.icon,
    required this.label,
    required this.done,
  });

  final IconData icon;
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          height: 44,
          decoration: BoxDecoration(
            color: done
                ? primary.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: done
                  ? primary.withValues(alpha: 0.5)
                  : AppTheme.cardBorder.withValues(alpha: 0.85),
            ),
          ),
          child: Icon(
            done ? Icons.check : icon,
            color: done ? primary : AppTheme.deepBlue,
            size: 19,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            color: done ? primary : AppTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── 今日关键指标行 ─────────────────────────────────────────────
class _TodayMetricsRow extends StatelessWidget {
  const _TodayMetricsRow({required this.data, required this.onAddIndicator});
  final HealthDashboardData? data;
  final VoidCallback onAddIndicator;

  @override
  Widget build(BuildContext context) {
    final profile = data?.profile;
    final bmi = profile?.bmi ?? 0;
    final latestBp = data?.latestIndicator('bp');
    final latestWeight = data?.latestIndicator('weight');
    final latestGlucose = data?.latestIndicator('glucose');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('今日数据',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          TextButton.icon(
            onPressed: onAddIndicator,
            icon: const Icon(Icons.add, size: 15),
            label: const Text('录入', style: TextStyle(fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (_, c) {
          final cols = c.maxWidth >= 500 ? 4 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: cols == 4 ? 1.7 : 1.5,
            children: [
              _MetricTile(
                  label: 'BMI',
                  value: bmi == 0 ? '--' : bmi.toStringAsFixed(1),
                  sub: profile?.bmiLevel ?? '待完善',
                  icon: Icons.monitor_weight_outlined,
                  color: Colors.teal),
              _MetricTile(
                  label: '血压',
                  value: latestBp?.displayValue ?? '--',
                  sub: latestBp == null
                      ? '未录入'
                      : DateFormat('MM/dd').format(latestBp.measuredTime),
                  icon: Icons.favorite_outline,
                  color: Colors.redAccent),
              _MetricTile(
                  label: '体重',
                  value: latestWeight?.displayValue ?? '--',
                  sub: latestWeight == null
                      ? '未录入'
                      : DateFormat('MM/dd').format(latestWeight.measuredTime),
                  icon: Icons.scale_outlined,
                  color: AppTheme.deepBlue),
              _MetricTile(
                  label: '血糖',
                  value: latestGlucose?.displayValue ?? '--',
                  sub: latestGlucose == null
                      ? '未录入'
                      : DateFormat('MM/dd').format(latestGlucose.measuredTime),
                  icon: Icons.water_drop_outlined,
                  color: Colors.orange),
            ],
          );
        }),
      ]),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(
      {required this.label,
      required this.value,
      required this.sub,
      required this.icon,
      required this.color});
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 14, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text(sub,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ── 今日计划摘要卡片 ──────────────────────────────────────────
class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard(
      {required this.meal,
      required this.exercise,
      required this.onGenerate,
      required this.onViewAll});
  final PlanRecordData? meal;
  final PlanRecordData? exercise;
  final VoidCallback onGenerate;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final hasPlan = meal != null || exercise != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('今日计划',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          TextButton(onPressed: onViewAll, child: const Text('全部计划')),
        ]),
        const SizedBox(height: 8),
        if (!hasPlan) ...[
          const Text('暂无今日计划，点击下方按钮生成 7 天方案',
              style: TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onGenerate,
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('生成 7 天计划'),
            ),
          ),
        ] else ...[
          if (meal != null)
            _PlanSummaryRow(
                type: '饮食',
                icon: Icons.restaurant_outlined,
                color: Colors.orange,
                summary: meal!.summary),
          if (meal != null && exercise != null) const SizedBox(height: 8),
          if (exercise != null)
            _PlanSummaryRow(
                type: '运动',
                icon: Icons.directions_run_outlined,
                color: Colors.green,
                summary: exercise!.summary),
        ],
      ]),
    );
  }
}

class _PlanSummaryRow extends StatelessWidget {
  const _PlanSummaryRow(
      {required this.type,
      required this.icon,
      required this.color,
      required this.summary});
  final String type;
  final IconData icon;
  final Color color;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('今日$type',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 13)),
          const SizedBox(height: 2),
          Text(summary,
              style: const TextStyle(
                  color: AppTheme.muted, fontSize: 12, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}

class _FoodDiaryPanel extends StatelessWidget {
  const _FoodDiaryPanel({
    required this.selectedDate,
    required this.records,
    required this.targets,
    required this.onDateChanged,
    required this.onRecord,
    required this.onOpenCalendar,
    required this.onOpenRecord,
  });

  final DateTime selectedDate;
  final List<MealRecordData> records;
  final DailyNutritionTargets targets;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<String> onRecord;
  final VoidCallback onOpenCalendar;
  final ValueChanged<MealRecordData> onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final consumed =
        records.fold<double>(0, (sum, item) => sum + item.totalCalories);
    final protein = records.fold<double>(0, (sum, item) => sum + item.proteinG);
    final carbs = records.fold<double>(0, (sum, item) => sum + item.carbsG);
    final fat = records.fold<double>(0, (sum, item) => sum + item.fatG);
    final hasTargets = targets.calories > 0;
    final remaining = hasTargets
        ? (targets.calories - consumed).clamp(0, 9999).toDouble()
        : -1.0;

    return _Panel(
      title: '每日饮食',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '饮食日历',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: onOpenCalendar,
          ),
          IconButton(
            tooltip: '加一道菜',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => onRecord(_defaultMealType()),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _MealCalendarBar(
            selectedDate: selectedDate, onDateChanged: onDateChanged),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FBFF),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('已摄入',
                          style: TextStyle(color: AppTheme.muted)),
                      Text(consumed.round().toString(),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w900)),
                    ]),
              ),
              MacroRing(
                calories: remaining,
                proteinG: protein,
                carbsG: carbs,
                fatG: fat,
                size: 112,
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: const [
                      Text('已消耗', style: TextStyle(color: AppTheme.muted)),
                      Text('0',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w900)),
                    ]),
              ),
            ]),
            const SizedBox(height: 14),
            _NutritionProgress(
              label: '蛋白质',
              value: protein,
              target: targets.proteinG,
              color: Color(0xFF19B43B),
            ),
            const SizedBox(height: 10),
            _NutritionProgress(
              label: '碳水化合物',
              value: carbs,
              target: targets.carbsG,
              color: Color(0xFFF59E0B),
            ),
            const SizedBox(height: 10),
            _NutritionProgress(
              label: '脂肪',
              value: fat,
              target: targets.fatG,
              color: Color(0xFFFACC15),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        for (final section in const [
          ('breakfast', '早餐', 0.30),
          ('lunch', '午餐', 0.40),
          ('dinner', '晚餐', 0.30),
        ]) ...[
          _MealSectionCard(
            mealType: section.$1,
            title: section.$2,
            limitCalories: targets.calories * section.$3,
            records:
                records.where((item) => item.mealType == section.$1).toList(),
            onRecord: () => onRecord(section.$1),
            onOpen: onOpenRecord,
          ),
          if (section.$1 != 'dinner') const SizedBox(height: 12),
        ],
      ]),
    );
  }

  String _defaultMealType() {
    final hour = DateTime.now().hour;
    if (hour < 10) return 'breakfast';
    if (hour < 15) return 'lunch';
    return 'dinner';
  }
}

class _MealCalendarBar extends StatelessWidget {
  const _MealCalendarBar({
    required this.selectedDate,
    required this.onDateChanged,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 3));
    final dates = [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final date = dates[index];
          final selected = _sameDay(date, selectedDate);
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onDateChanged(date),
            child: Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primaryBlue.withValues(alpha: 0.16)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AppTheme.primaryBlue : AppTheme.cardBorder,
                ),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                        DateFormat('E', 'zh_CN')
                            .format(date)
                            .replaceAll('周', ''),
                        style: TextStyle(
                          color: selected ? AppTheme.deepBlue : AppTheme.muted,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 4),
                    Text('${date.day}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: selected ? AppTheme.deepBlue : AppTheme.ink,
                        )),
                  ]),
            ),
          );
        },
      ),
    );
  }
}

class _MealCalendarDialog extends StatelessWidget {
  const _MealCalendarDialog({
    required this.selectedDate,
    required this.records,
    required this.onPickDate,
  });

  final DateTime selectedDate;
  final List<MealRecordData> records;
  final Future<DateTime?> Function() onPickDate;

  @override
  Widget build(BuildContext context) {
    final total =
        records.fold<double>(0, (sum, item) => sum + item.totalCalories);
    return AlertDialog(
      title: const Text('饮食日历'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    DateFormat('yyyy年MM月dd日 EEEE', 'zh_CN')
                        .format(selectedDate),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text('${total.round()} kcal',
                    style: const TextStyle(
                        color: AppTheme.deepBlue, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 12),
              if (records.isEmpty)
                const Text('这一天还没有饮食记录。',
                    style: TextStyle(color: AppTheme.muted))
              else
                for (final group in const [
                  ('breakfast', '早餐'),
                  ('lunch', '午餐'),
                  ('dinner', '晚餐'),
                ]) ...[
                  _MealCalendarGroup(
                    title: group.$2,
                    records: records
                        .where((item) => item.mealType == group.$1)
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                ],
            ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final picked = await onPickDate();
            if (context.mounted && picked != null) {
              Navigator.pop(context, picked);
            }
          },
          icon: const Icon(Icons.calendar_month_outlined, size: 16),
          label: const Text('选择日期'),
        ),
      ],
    );
  }
}

class _MealCalendarGroup extends StatelessWidget {
  const _MealCalendarGroup({required this.title, required this.records});

  final String title;
  final List<MealRecordData> records;

  @override
  Widget build(BuildContext context) {
    final calories =
        records.fold<double>(0, (sum, item) => sum + item.totalCalories);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$title · ${calories.round()} kcal',
          style: const TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      if (records.isEmpty)
        const Text('暂无记录',
            style: TextStyle(color: AppTheme.muted, fontSize: 12))
      else
        for (final record in records)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${record.name} · ${record.totalCalories.round()} kcal',
                style: const TextStyle(color: AppTheme.muted)),
          ),
    ]);
  }
}

class _NutritionProgress extends StatelessWidget {
  const _NutritionProgress({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  final String label;
  final double value;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w800))),
        Text(
            target <= 0
                ? '${value.toStringAsFixed(1)} / -- 克'
                : '${value.toStringAsFixed(1)} / ${target.toStringAsFixed(1)}克',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      ]),
      const SizedBox(height: 5),
      LinearProgressIndicator(
        value: pct,
        color: color,
        backgroundColor: color.withValues(alpha: 0.14),
        minHeight: 6,
        borderRadius: BorderRadius.circular(99),
      ),
    ]);
  }
}

class _MealSectionCard extends StatelessWidget {
  const _MealSectionCard({
    required this.mealType,
    required this.title,
    required this.limitCalories,
    required this.records,
    required this.onRecord,
    required this.onOpen,
  });

  final String mealType;
  final String title;
  final double limitCalories;
  final List<MealRecordData> records;
  final VoidCallback onRecord;
  final ValueChanged<MealRecordData> onOpen;

  @override
  Widget build(BuildContext context) {
    final total =
        records.fold<double>(0, (sum, item) => sum + item.totalCalories);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_mealIcon(mealType), color: AppTheme.deepBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
              Text(
                  limitCalories <= 0
                      ? '${total.round()} / -- kcal'
                      : '${total.round()} / ${limitCalories.round()} kcal',
                  style: const TextStyle(color: AppTheme.muted)),
            ]),
          ),
          OutlinedButton(onPressed: onRecord, child: const Text('加菜')),
        ]),
        if (records.isNotEmpty) ...[
          const Divider(height: 22),
          for (final record in records)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => onOpen(record),
              leading: CircleAvatar(
                backgroundColor: AppTheme.pageBg,
                child: const Icon(Icons.search, color: AppTheme.deepBlue),
              ),
              title: Text(record.name,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${record.totalCalories.round()} kcal，1份'),
              trailing: const Icon(Icons.chevron_right),
            ),
        ],
      ]),
    );
  }

  IconData _mealIcon(String type) => switch (type) {
        'breakfast' => Icons.breakfast_dining_outlined,
        'dinner' => Icons.dinner_dining_outlined,
        _ => Icons.lunch_dining_outlined,
      };
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ── 快捷入口按钮 ──────────────────────────────────────────────
class _QuickEntry extends StatelessWidget {
  const _QuickEntry(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ── 最近打卡列表 ──────────────────────────────────────────────
class _RecentClockList extends StatelessWidget {
  const _RecentClockList({required this.records});
  final List<ClockRecordData> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('今日暂无打卡，点击"打卡"标签开始记录。',
            style: TextStyle(color: AppTheme.muted, fontSize: 13)),
      );
    }
    final typeIcon = {
      'meal': Icons.restaurant_outlined,
      'exercise': Icons.directions_run_outlined,
      'medicine': Icons.medication_outlined,
      'weight': Icons.scale_outlined,
      'water': Icons.water_drop_outlined,
    };
    return Column(children: [
      for (final r in records.take(5))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(typeIcon[r.type] ?? Icons.check_circle_outline,
                  color: AppTheme.deepBlue, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(r.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  if (r.note.isNotEmpty)
                    Text(r.note,
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ])),
            Text(DateFormat('HH:mm').format(r.clockTime),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ]),
        ),
    ]);
  }
}

// ── 提醒预览 ──────────────────────────────────────────────────
class _ReminderPreview extends StatelessWidget {
  const _ReminderPreview({required this.reminders});
  final List<ReminderData> reminders;

  static const _collapsedCount = 3;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final reminders = this.reminders.where((reminder) {
      final time = reminder.remindTime;
      final isUpcomingToday = time.hour > now.hour ||
          (time.hour == now.hour && time.minute > now.minute);
      return isUpcomingToday && reminder.occursOn(now);
    }).toList(growable: false)
      ..sort((a, b) {
        final aMinutes = a.remindTime.hour * 60 + a.remindTime.minute;
        final bMinutes = b.remindTime.hour * 60 + b.remindTime.minute;
        return aMinutes.compareTo(bMinutes);
      });

    if (reminders.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.pageBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text('今天暂无待提醒事项。',
            style: TextStyle(color: AppTheme.muted, fontSize: 13)),
      );
    }
    final visible = reminders.take(_collapsedCount).toList(growable: false);
    return Column(children: [
      for (final r in visible)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.pageBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.notifications_active_outlined,
                    color: AppTheme.deepBlue, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(r.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13))),
              Text(r.timeText,
                  style: const TextStyle(
                      color: AppTheme.deepBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ]),
          ),
        ),
    ]);
  }
}

// ── 最近指标（近 3 天，可收放） ────────────────────────────────
class _RecentIndicatorsPanel extends StatelessWidget {
  const _RecentIndicatorsPanel({
    required this.indicators,
    required this.onAdd,
    required this.onViewAll,
  });

  final List<HealthIndicatorEntry> indicators;
  final VoidCallback onAdd;
  final VoidCallback onViewAll;

  static const _maxShow = 6;

  static const _typeIcon = {
    'weight': (Icons.scale_outlined, Colors.blue),
    'bp': (Icons.favorite_outline, Colors.redAccent),
    'glucose': (Icons.water_drop_outlined, Colors.orange),
    'heart_rate': (Icons.monitor_heart_outlined, Colors.pink),
    'lipid': (Icons.science_outlined, Colors.purple),
    'body_fat': (Icons.person_outlined, Colors.teal),
    'waist': (Icons.straighten_outlined, Colors.brown),
    'spo2': (Icons.air_outlined, Colors.lightBlue),
    'sleep': (Icons.bedtime_outlined, Colors.indigo),
    'steps': (Icons.directions_walk_outlined, Colors.green),
  };

  @override
  Widget build(BuildContext context) {
    final visible = indicators.take(_maxShow).toList();

    return _Panel(
      title: '最近指标',
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(onPressed: onViewAll, child: const Text('全部')),
        IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            iconSize: 18,
            visualDensity: VisualDensity.compact),
      ]),
      child: indicators.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Expanded(
                  child: Text('暂无指标记录',
                      style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('录入', style: TextStyle(fontSize: 13)),
                ),
              ]),
            )
          : Column(children: [
              for (final e in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: (_typeIcon[e.type]?.$2 ?? Colors.grey)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        _typeIcon[e.type]?.$1 ?? Icons.monitor_heart_outlined,
                        color: _typeIcon[e.type]?.$2 ?? Colors.grey,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(e.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(e.displayValue,
                              style: const TextStyle(
                                  color: AppTheme.muted, fontSize: 12)),
                        ])),
                    Text(
                      DateFormat('MM/dd HH:mm').format(e.measuredTime),
                      style:
                          const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ]),
                ),
              if (indicators.length > _maxShow)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: GestureDetector(
                    onTap: onViewAll,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.pageBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '查看全部 ${indicators.length} 条记录',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.deepBlue,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.chevron_right,
                                size: 16, color: AppTheme.deepBlue),
                          ]),
                    ),
                  ),
                ),
            ]),
    );
  }
}

// ── 面板容器 ──────────────────────────────────────────────────
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFFDFEFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.deepBlue.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800))),
          if (action != null) action!,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
