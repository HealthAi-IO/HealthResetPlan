import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_settings_controller.dart';
import '../../app/app_theme.dart';
import '../../app/theme_controller.dart';
import '../../core/auth/user_session.dart';
import '../../core/content/site_message_service.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/notification/reminder_scheduler.dart';
import '../../core/widgets/motion.dart';
import '../meals/meal_input_args.dart';
import '../meals/macro_ring.dart';

part 'home_widgets.dart';

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

class WelcomeLetterPage extends StatelessWidget {
  const WelcomeLetterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('欢迎信')),
      body: SafeArea(
        child: _WelcomeLetterContent(
          onStart: () => context.push('/profile?guideProfile=1'),
          onLater: () => context.pop(),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _profilePromptDismissedKey = 'home_profile_prompt_dismissed_v1';
  static const _profilePromptSnoozedUntilKey =
      'home_profile_prompt_snoozed_until_v1';
  static const _indicatorPromptSnoozedUntilKey =
      'home_indicator_prompt_snoozed_until_v2';
  final HealthRepository _repo = sl<HealthRepository>();

  HealthDashboardData? _data;
  List<HealthIndicatorEntry> _recentIndicators = const [];
  List<MealRecordData> _mealRecords = const [];
  List<MealRecordData> _todayMealRecords = const [];
  List<HealthReportRecord> _recentReports = const [];
  HealthTrendAlert? _healthAlert;
  DateTime _selectedMealDate = DateTime.now();
  bool _loading = true;
  String? _loadError;
  bool _promptOpen = false;
  bool _entryPromptsRunning = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChanged);
    appSettingsController.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_onChanged);
    appSettingsController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 3));
      final results = await Future.wait<Object?>([
        _repo.loadDashboard(),
        _repo.loadIndicatorsSince(cutoff),
        _repo.loadMealsForDate(_selectedMealDate),
        _repo.loadReportRecords(limit: 3),
        _repo.loadMealsForDate(DateTime.now()),
        _repo.loadPriorityHealthAlert(),
      ]).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _data = results[0] as HealthDashboardData;
        _recentIndicators = results[1] as List<HealthIndicatorEntry>;
        _mealRecords = results[2] as List<MealRecordData>;
        _recentReports = results[3] as List<HealthReportRecord>;
        _todayMealRecords = results[4] as List<MealRecordData>;
        _healthAlert = results[5] as HealthTrendAlert?;
        _loadError = null;
        _loading = false;
      });
      _runEntryPrompts(results[0] as HealthDashboardData);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = '暂时无法加载首页数据，请检查网络后重试。';
        _loading = false;
      });
    }
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
    final dismissedKey = _userPreferenceKey(prompt.dismissedKey);
    final snoozedKey = _userPreferenceKey(
      isIndicatorPrompt
          ? _indicatorPromptSnoozedUntilKey
          : _profilePromptSnoozedUntilKey,
    );
    if (isIndicatorPrompt ||
        prompt.confirmAction == _HomePromptAction.profile) {
      final snoozedUntil = prefs.getInt(snoozedKey) ?? 0;
      if (snoozedUntil > DateTime.now().millisecondsSinceEpoch) return;
    }
    if (prefs.getBool(dismissedKey) == true) {
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
          snoozedKey,
          DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch,
        );
      } else {
        await prefs.setBool(dismissedKey, true);
      }
    } else if (action == _HomePromptAction.later &&
        prompt.confirmAction == _HomePromptAction.profile) {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await prefs.setInt(
        snoozedKey,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day)
            .millisecondsSinceEpoch,
      );
    } else if (action == _HomePromptAction.profile) {
      await context.push('/profile?guideProfile=1');
      if (mounted) await _load(silent: true);
    } else if (action == _HomePromptAction.indicator) {
      context.push('/indicators/input').then((_) {
        if (mounted) _load(silent: true);
      });
    }
  }

  _HomePrompt? _nextPrompt(HealthDashboardData data) {
    final profile = data.profile;
    if (profile == null || !profile.isComplete) {
      final missingFields = <String>[
        if (profile == null ||
            (profile.gender != 'female' && profile.gender != 'male'))
          '性别',
        if (profile == null || profile.age < HealthRanges.minAge) '出生年份',
        if (profile == null ||
            profile.heightCm < HealthRanges.minHeightCm ||
            profile.heightCm > HealthRanges.maxHeightCm)
          '身高',
        if (profile == null ||
            profile.weightKg < HealthRanges.minWeightKg ||
            profile.weightKg > HealthRanges.maxWeightKg)
          '体重',
      ];
      return _HomePrompt(
        dismissedKey: _profilePromptDismissedKey,
        title: '先填写你的健康数据',
        content: '还需完善：${missingFields.join('、')}。填写后，系统会生成更准确的健康建议。',
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

  String _userPreferenceKey(String key) =>
      '${key}_${UserSession.instance.userId ?? kLocalUserId}';

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

  // ignore: unused_element
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
      context.push('/profile?guideProfile=1').then((_) {
        if (mounted) _load(silent: true);
      });
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

  void _openIndicator([String? type]) {
    context.push('/indicators/input', extra: type).then((_) {
      if (mounted) _load(silent: true);
    });
  }

  void _openHomeTask(HomeTodayTaskData task) {
    switch (task.type) {
      case 'meal':
        final mealType = task.nextMealType;
        if (mealType == null) {
          context.go('/meals');
          return;
        }
        context
            .push(
          '/meals/input',
          extra: MealInputArgs(mealType: mealType, eatenDate: DateTime.now()),
        )
            .then((_) {
          if (mounted) _load(silent: true);
        });
        return;
      case 'weight':
        _openIndicator('weight');
        return;
      case 'medicine':
        final reminderId = task.reminderId;
        context.go(reminderId == null
            ? '/records?view=clock&manage=rules'
            : '/records?view=clock&reminderId=$reminderId');
        return;
      case 'exercise':
        if (!task.requiredToday) {
          context.go('/plan');
          return;
        }
        context.go('/records?view=clock');
        return;
      default:
        context.go('/clock');
        return;
    }
  }

  Future<void> _takeSeniorMedicine(
    ReminderData reminder,
    DateTime occurrence,
  ) async {
    try {
      final updated = await _repo.recordMedicationAction(
        reminder,
        'taken',
        scheduledAt: occurrence,
      );
      await sl<ReminderScheduler>().syncReminder(updated);
      if (!mounted) return;
      final refill = updated.refillNeeded ? '，库存不足，请及时补充' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已记录服药$refill')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('记录失败，请检查网络后重试')),
        );
      }
    }
  }

  Future<void> _acknowledgeSeniorReminder(
    ReminderData reminder,
    DateTime occurrence,
  ) async {
    try {
      final updated = await _repo.acknowledgeReminder(reminder, occurrence);
      await sl<ReminderScheduler>().syncReminder(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已完成今天这项提醒')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('记录失败，请检查网络后重试')),
        );
      }
    }
  }

  Future<void> _showThemePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: AnimatedBuilder(
          animation: themeController,
          builder: (context, _) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('选择主题', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '颜色和深浅模式会立即应用，并在下次打开时保留。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (final item in AppColorTheme.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: item.seed),
                  title: Text(item.label),
                  trailing: themeController.colorTheme == item
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: () => themeController.select(item),
                ),
              const Divider(),
              for (final item in const [
                (
                  mode: AppThemeMode.system,
                  icon: Icons.brightness_auto_outlined,
                  title: '跟随系统',
                  subtitle: '根据手机设置自动切换',
                ),
                (
                  mode: AppThemeMode.light,
                  icon: Icons.light_mode_outlined,
                  title: '浅色模式',
                  subtitle: '始终使用浅色外观',
                ),
                (
                  mode: AppThemeMode.dark,
                  icon: Icons.dark_mode_outlined,
                  title: '深色模式',
                  subtitle: '适合夜间或低光环境',
                ),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(item.icon),
                  title: Text(item.title),
                  subtitle: Text(item.subtitle),
                  trailing: themeController.selectedThemeMode == item.mode
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: () => themeController.setThemeMode(item.mode),
                ),
            ],
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
    if (_loadError != null && _data == null) {
      return _HomeLoadFailureView(onRetry: _load);
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
    final todayExercise =
        todayPlans.where((p) => p.type == 'exercise').firstOrNull;
    final todayMeasurement =
        todayPlans.where((p) => p.type == 'measurement').firstOrNull;
    final todayMeal = todayPlans.where((p) => p.type == 'meal').firstOrNull;

    // 今日打卡
    final todayClocks = (data?.clockRecords ?? []).where((r) {
      final t = r.clockTime;
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).toList();
    final doneTypes =
        todayClocks.where((r) => r.status == 'done').map((r) => r.type).toSet();
    final todayTasks = buildHomeTodayTasks(
      date: now,
      plans: data?.plans ?? const [],
      reminders: data?.reminders ?? const [],
      clockRecords: todayClocks,
      mealRecords: _todayMealRecords,
      indicators: data?.indicators ?? const [],
    );
    final completion = homeTodayTaskCompletion(todayTasks);
    final desktop = MediaQuery.sizeOf(context).width >= 1280;
    final seniorMode = appSettingsController.seniorMode;

    if (seniorMode) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const PageStorageKey('senior-home-scroll'),
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '今天',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '你好，${profile?.nickname.trim().isNotEmpty == true ? profile!.nickname.trim() : '健康用户'} · $todayLabel',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '选择主题',
                  onPressed: _showThemePicker,
                  icon: const Icon(Icons.palette_outlined),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_loadError != null) ...[
              _HomeLoadErrorBanner(onRetry: _load),
              const SizedBox(height: 14),
            ],
            if (_healthAlert != null) ...[
              _HealthAlertCard(
                alert: _healthAlert!,
                onRecord: () => context.push('/indicators/input'),
              ),
              const SizedBox(height: 14),
            ],
            _SeniorTodayTasks(
              plans: todayPlans,
              reminders: data?.reminders ?? const [],
              doneTypes: doneTypes,
              onTakeMedicine: _takeSeniorMedicine,
              onAcknowledge: _acknowledgeSeniorReminder,
              onOpenClock: () => context.go('/clock'),
            ),
            const SizedBox(height: 14),
            _SeniorMetrics(
              data: data,
              onRecord: _openIndicator,
            ),
            const SizedBox(height: 14),
            _SeniorQuickRecord(onRecord: _openIndicator),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => context.go('/clock'),
              icon: const Icon(Icons.task_alt_outlined),
              label: Text(
                '今日已完成 ${todayClocks.where((item) => item.status == 'done').length} 项　查看记录',
              ),
            ),
          ],
        ),
      );
    }

    if (desktop) {
      return _DesktopHomeDashboard(
        data: data,
        reports: _recentReports,
        tasks: todayTasks,
        completion: completion,
        todayLabel: todayLabel,
        onRefresh: _load,
        onMealRecord: _openMealInput,
        onTaskTap: _openHomeTask,
        onOpenPlan: () => context.go('/plan'),
        onOpenClock: () => context.go('/clock'),
        onOpenStats: () => context.go('/stats'),
        onOpenReports: () => context.push('/report'),
        onOpenContent: () => context.push('/content'),
        onOpenLetter: _openWelcomeLetter,
        onThemeTap: _showThemePicker,
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
          _HomeTopBar(
            profile: profile,
            todayLabel: todayLabel,
            onThemeTap: _showThemePicker,
          ),
          const SizedBox(height: 12),
          if (_loadError != null) ...[
            _HomeLoadErrorBanner(onRetry: _load),
            const SizedBox(height: 14),
          ],
          _DashboardHero(
            tasks: todayTasks,
            onTaskTap: _openHomeTask,
          ),
          const SizedBox(height: 14),
          _AiBenefitsBanner(onTap: () => context.push('/ai-benefits')),
          const SizedBox(height: 14),
          _Panel(
            title: '常用功能',
            child: LayoutBuilder(builder: (_, c) {
              final cols = c.maxWidth >= 600 ? 3 : 3;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: c.maxWidth >= 700 ? 1.8 : 0.95,
                children: [
                  _QuickEntry(
                      icon: Icons.document_scanner_outlined,
                      label: '报告识别',
                      color: Colors.teal,
                      onTap: () => context.push('/report')),
                  _QuickEntry(
                      icon: Icons.smart_toy_outlined,
                      label: '健康管家 AI',
                      color: AppTheme.aiPurple,
                      onTap: () => context.push('/chat')),
                  _QuickEntry(
                      icon: Icons.health_and_safety_outlined,
                      label: '健康自检',
                      color: Colors.green,
                      onTap: () => context.push('/self-check')),
                ],
              );
            }),
          ),
          const SizedBox(height: 14),
          _TodayPlanCard(
            exercise: todayExercise,
            measurement: todayMeasurement,
            meal: todayMeal,
            onGenerate: () async {
              try {
                await _repo.generateWeeklyPlan();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已生成 7 天本地计划')),
                );
              } on PlanBlockedException catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error.message)));
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('计划生成失败，请重试')),
                );
              }
            },
            onViewAll: () => context.go('/plan'),
          ),
          const SizedBox(height: 14),
          if (_healthAlert != null) ...[
            _HealthAlertCard(
              alert: _healthAlert!,
              onRecord: () => context.push('/indicators/input'),
            ),
            const SizedBox(height: 14),
          ],
          _TodayMetricsRow(
            data: data,
            onAddIndicator: () {
              context.push('/indicators/input').then((_) {
                if (mounted) _load(silent: true);
              });
            },
          ),
          const SizedBox(height: 14),
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
          _FoodHomeSummary(
            records: _todayMealRecords,
            targets: DailyNutritionTargets.fromProfile(profile),
            onOpen: () => context.go('/meals'),
          ),
          const SizedBox(height: 14),
          _WeeklyContentCard(onTap: () => context.push('/content')),
          const SizedBox(height: 14),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
