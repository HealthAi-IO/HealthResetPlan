part of 'home_page.dart';

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
    required this.onThemeTap,
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
  final VoidCallback onThemeTap;
  final VoidCallback onAddIndicator;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
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
                    Text(todayLabel, style: TextStyle(color: AppTheme.muted)),
                  ],
                ),
              ),
              Text(
                '今日完成 $completed 项',
                style: TextStyle(color: primary, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                tooltip: '选择主题',
                onPressed: onThemeTap,
                icon: const Icon(Icons.palette_outlined, size: 20),
              ),
              const SizedBox(width: 8),
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
                        style: TextStyle(color: AppTheme.muted, fontSize: 13),
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
                                    style: TextStyle(
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
                              style: TextStyle(
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
                            Text(
                              '今天，从一项记录开始',
                              style: TextStyle(
                                color: AppTheme.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
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
      color: colors.surfaceContainerLow,
      elevation: 2,
      shadowColor: AppTheme.softShadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colors.primary.withValues(alpha: 0.14),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '写给正在重新出发的你',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '健康不是突然改变，而是在一次次行动中慢慢找回来。',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
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
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.auto_stories_outlined, color: primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '每周健康科普',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '用轻量卡片了解饮食、运动、睡眠与健康习惯',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
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
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
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
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
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
                  DateFormat('MM/dd HH:mm').format(indicators[i].measuredTime),
                  style: TextStyle(color: AppTheme.muted, fontSize: 12),
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
            Text(text, style: TextStyle(color: AppTheme.muted, fontSize: 13)),
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

class _HomeLoadFailureView extends StatelessWidget {
  const _HomeLoadFailureView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 40,
                color: AppTheme.muted,
              ),
              const SizedBox(height: 12),
              const Text('暂时无法加载首页数据'),
              const SizedBox(height: 6),
              Text('请检查网络后重试。', style: TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
}

class _HomeLoadErrorBanner extends StatelessWidget {
  const _HomeLoadErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.softBlue,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.muted),
            const SizedBox(width: 8),
            const Expanded(child: Text('部分首页数据未更新，请重试。')),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
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

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.profile,
    required this.todayLabel,
    required this.onThemeTap,
  });

  final UserProfileData? profile;
  final String todayLabel;
  final VoidCallback onThemeTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = (profile?.nickname.isNotEmpty == true)
        ? profile!.nickname
        : UserSession.instance.name;
    final displayName = name.trim().isEmpty ? '健康用户' : name.trim();
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: '打开个人与功能菜单',
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '你好，$displayName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                todayLabel,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const _HomeMessageButton(),
        IconButton(
          tooltip: '选择主题',
          onPressed: onThemeTap,
          icon: const Icon(Icons.palette_outlined),
        ),
      ],
    );
  }
}

class _HomeMessageButton extends StatelessWidget {
  const _HomeMessageButton();

  @override
  Widget build(BuildContext context) {
    if (!sl.isRegistered<SiteMessageService>()) {
      return IconButton(
        tooltip: '消息中心',
        onPressed: () => context.push('/messages'),
        icon: const Icon(Icons.notifications_outlined),
      );
    }
    final service = sl<SiteMessageService>();
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => IconButton(
        tooltip: '消息中心',
        onPressed: () => context.push('/messages'),
        icon: Badge(
          isLabelVisible: service.unreadCount > 0,
          label:
              Text(service.unreadCount > 99 ? '99+' : '${service.unreadCount}'),
          child: const Icon(Icons.notifications_outlined),
        ),
      ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.completion,
    required this.doneTypes,
    required this.onNextAction,
  });

  final double completion;
  final Set<String> doneTypes;
  final VoidCallback onNextAction;

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
    final nextAction = !doneTypes.contains('meal')
        ? '记录今天的饮食'
        : !doneTypes.contains('weight')
            ? '记录一次体重'
            : completion < 1
                ? '完成下一项打卡'
                : '查看明天的计划';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.accentSoftGradient(context),
        border: Border.all(color: primary.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日概览',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      completion >= 1 ? '今天的任务已完成' : '完成一项，就离目标更近一步',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              _ProgressRing(value: completion, size: 68, color: primary),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var index = 0; index < _clockItems.length; index++) ...[
                Expanded(
                  child: _HomeStatusItem(
                    icon: _clockItems[index].$3,
                    label: _clockItems[index].$2,
                    done: doneTypes.contains(_clockItems[index].$1),
                  ),
                ),
                if (index < _clockItems.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onNextAction,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(nextAction),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeStatusItem extends StatelessWidget {
  const _HomeStatusItem({
    required this.icon,
    required this.label,
    required this.done,
  });

  final IconData icon;
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: done
            ? colors.primaryContainer.withValues(alpha: 0.8)
            : colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: done
              ? colors.primary.withValues(alpha: 0.38)
              : colors.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Icon(
            done ? Icons.check_rounded : icon,
            color: done ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: done ? colors.primary : colors.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
    return Semantics(
      label: '今日记录完成度 $pct%',
      child: ExcludeSemantics(
        child: SizedBox(
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
                      color: color, fontWeight: FontWeight.w700, fontSize: 18)),
              Text('完成', style: TextStyle(color: AppTheme.muted, fontSize: 10)),
            ]),
          ]),
        ),
      ),
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

// ── 今日关键指标行 ─────────────────────────────────────────────
class _TodayMetricsRow extends StatelessWidget {
  const _TodayMetricsRow({required this.data, required this.onAddIndicator});
  final HealthDashboardData? data;
  final VoidCallback onAddIndicator;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = data?.profile;
    final bmi = profile?.bmi ?? 0;
    final latestBp = data?.latestIndicator('bp');
    final latestWeight = data?.latestIndicator('weight');
    final latestGlucose = data?.latestIndicator('glucose');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(color: colors.outlineVariant),
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
                      : DateFormat('MM/dd HH:mm').format(latestBp.measuredTime),
                  icon: Icons.favorite_outline,
                  color: Colors.redAccent),
              _MetricTile(
                  label: '体重',
                  value: latestWeight?.displayValue ?? '--',
                  sub: latestWeight == null
                      ? '未录入'
                      : DateFormat('MM/dd HH:mm')
                          .format(latestWeight.measuredTime),
                  icon: Icons.scale_outlined,
                  color: AppTheme.deepBlue),
              _MetricTile(
                  label: '血糖',
                  value: latestGlucose?.displayValue ?? '--',
                  sub: latestGlucose == null
                      ? '未录入'
                      : DateFormat('MM/dd HH:mm')
                          .format(latestGlucose.measuredTime),
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
            style: TextStyle(color: AppTheme.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ── 今日计划摘要卡片 ──────────────────────────────────────────
class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard(
      {required this.exercise,
      required this.measurement,
      required this.onGenerate,
      required this.onViewAll});
  final PlanRecordData? exercise;
  final PlanRecordData? measurement;
  final VoidCallback onGenerate;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final hasPlan = exercise != null || measurement != null;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
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
          Text('暂无今日计划，点击下方按钮生成 7 天方案',
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
          if (exercise != null)
            _PlanSummaryRow(
                type: '运动',
                icon: Icons.directions_run_outlined,
                color: Colors.green,
                summary: exercise!.summary),
          if (exercise != null && measurement != null)
            const SizedBox(height: 8),
          if (measurement != null)
            _PlanSummaryRow(
              type: '测量',
              icon: Icons.monitor_heart_outlined,
              color: Colors.blue,
              summary: measurement!.summary,
            ),
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
              style:
                  TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}

class _FoodHomeSummary extends StatelessWidget {
  const _FoodHomeSummary({
    required this.records,
    required this.targets,
    required this.onOpen,
  });

  final List<MealRecordData> records;
  final DailyNutritionTargets targets;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final calories =
        records.fold<double>(0, (sum, item) => sum + item.totalCalories);
    final protein = records.fold<double>(0, (sum, item) => sum + item.proteinG);
    final cost = records.fold<double>(0, (sum, item) => sum + item.cost);
    return _Panel(
      title: '今日饮食',
      action: TextButton.icon(
        onPressed: onOpen,
        icon: const Icon(Icons.chevron_right),
        label: const Text('打开账本'),
      ),
      child: Row(children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.restaurant_menu, color: AppTheme.deepBlue),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${calories.toStringAsFixed(0)} kcal · ${records.length} 餐',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '蛋白质 ${protein.toStringAsFixed(0)}g${cost > 0 ? ' · 花费 ¥${cost.toStringAsFixed(2)}' : ''}',
              style: TextStyle(color: AppTheme.muted),
            ),
            if (targets.calories > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (calories / targets.calories).clamp(0, 1),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ignore: unused_element
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
                      Text('已摄入', style: TextStyle(color: AppTheme.muted)),
                      Text(consumed.round().toString(),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700)),
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
                    children: [
                      Text('已消耗', style: TextStyle(color: AppTheme.muted)),
                      Text('0',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700)),
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
                          fontWeight: FontWeight.w700,
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
                    style: TextStyle(
                        color: AppTheme.deepBlue, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 12),
              if (records.isEmpty)
                Text('这一天还没有饮食记录。', style: TextStyle(color: AppTheme.muted))
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
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (records.isEmpty)
        Text('暂无记录', style: TextStyle(color: AppTheme.muted, fontSize: 12))
      else
        for (final record in records)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${record.name} · ${record.totalCalories.round()} kcal',
                style: TextStyle(color: AppTheme.muted)),
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
            style: TextStyle(color: AppTheme.muted, fontSize: 12)),
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
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
                      fontWeight: FontWeight.w700, fontSize: 16)),
              Text(
                  limitCalories <= 0
                      ? '${total.round()} / -- kcal'
                      : '${total.round()} / ${limitCalories.round()} kcal',
                  style: TextStyle(color: AppTheme.muted)),
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
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                child: Icon(Icons.search, color: AppTheme.deepBlue),
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
// ignore: unused_element
class _RecentClockList extends StatelessWidget {
  const _RecentClockList({required this.records});
  final List<ClockRecordData> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Padding(
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
                        style: TextStyle(color: AppTheme.muted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ])),
            Text(_clockDateTimeLabel(r.clockTime),
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          ]),
        ),
    ]);
  }
}

String _clockDateTimeLabel(DateTime value) {
  final now = DateTime.now();
  if (DateUtils.isSameDay(value, now)) {
    return '今天 ${DateFormat('HH:mm').format(value)}';
  }
  return DateFormat('MM月dd日 HH:mm').format(value);
}

// ── 提醒预览 ──────────────────────────────────────────────────
// ignore: unused_element
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
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text('今天暂无待提醒事项。',
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
              color: Theme.of(context).scaffoldBackgroundColor,
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
                child: Icon(Icons.notifications_active_outlined,
                    color: AppTheme.deepBlue, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(r.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13))),
              Text(r.timeText,
                  style: TextStyle(
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
    'weight': Icons.scale_outlined,
    'bp': Icons.favorite_outline,
    'glucose': Icons.water_drop_outlined,
    'heart_rate': Icons.monitor_heart_outlined,
    'lipid': Icons.science_outlined,
    'body_fat': Icons.person_outlined,
    'waist': Icons.straighten_outlined,
    'spo2': Icons.air_outlined,
    'sleep': Icons.bedtime_outlined,
    'steps': Icons.directions_walk_outlined,
  };

  Color _typeColor(BuildContext context, String type) => switch (type) {
        'bp' || 'heart_rate' => Theme.of(context).colorScheme.error,
        'glucose' => AppTheme.warning(context),
        'lipid' ||
        'body_fat' ||
        'waist' =>
          Theme.of(context).colorScheme.tertiary,
        'spo2' => AppTheme.water(context),
        'steps' => AppTheme.exercise(context),
        _ => AppTheme.weight(context),
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
                Expanded(
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
                        color:
                            _typeColor(context, e.type).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        _typeIcon[e.type] ?? Icons.monitor_heart_outlined,
                        color: _typeColor(context, e.type),
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
                              style: TextStyle(
                                  color: AppTheme.muted, fontSize: 12)),
                        ])),
                    Text(
                      DateFormat('MM/dd HH:mm').format(e.measuredTime),
                      style: TextStyle(color: AppTheme.muted, fontSize: 12),
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
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '查看全部 ${indicators.length} 条记录',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.deepBlue,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.chevron_right,
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
class _SeniorTodayTasks extends StatelessWidget {
  const _SeniorTodayTasks({
    required this.plans,
    required this.reminders,
    required this.doneTypes,
    required this.onTakeMedicine,
    required this.onAcknowledge,
    required this.onOpenClock,
  });

  final List<PlanRecordData> plans;
  final List<ReminderData> reminders;
  final Set<String> doneTypes;
  final Future<void> Function(ReminderData, DateTime) onTakeMedicine;
  final Future<void> Function(ReminderData, DateTime) onAcknowledge;
  final VoidCallback onOpenClock;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final occurrences = <_SeniorReminderOccurrence>[];
    for (final reminder in reminders) {
      if (!reminder.isEnabled || !reminder.occursOn(now)) continue;
      for (final time in reminder.dailyTimes) {
        final occurrence = DateTime(
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        );
        if (reminder.type == 'medicine') {
          if (reminder.actionAt(occurrence) == null) {
            occurrences.add(_SeniorReminderOccurrence(reminder, occurrence));
          }
        } else if (occurrence.isAfter(now) &&
            !reminder.acknowledgedAt(occurrence)) {
          occurrences.add(_SeniorReminderOccurrence(reminder, occurrence));
        }
      }
    }
    occurrences.sort((a, b) => a.occurrence.compareTo(b.occurrence));
    final pendingPlans = plans
        .where((plan) =>
            (plan.type == 'meal' || plan.type == 'exercise') &&
            !doneTypes.contains(plan.type))
        .toList();
    const visibleLimit = 3;
    final visibleOccurrences = occurrences.take(visibleLimit).toList();
    final remainingSlots = visibleLimit - visibleOccurrences.length;
    final visiblePlans = pendingPlans.take(remainingSlots).toList();
    final hiddenCount = occurrences.length +
        pendingPlans.length -
        visibleOccurrences.length -
        visiblePlans.length;

    return _Panel(
      title: '今天要做',
      action: TextButton(onPressed: onOpenClock, child: const Text('全部')),
      child: occurrences.isEmpty && pendingPlans.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.task_alt, color: Colors.green),
                  SizedBox(width: 10),
                  Expanded(child: Text('今天暂时没有未完成事项。')),
                ],
              ),
            )
          : Column(
              children: [
                for (final item in visibleOccurrences)
                  _SeniorReminderTask(
                    item: item,
                    onTakeMedicine: onTakeMedicine,
                    onAcknowledge: onAcknowledge,
                    onOpenClock: onOpenClock,
                  ),
                for (final plan in visiblePlans)
                  _SeniorPlanTask(plan: plan, onTap: onOpenClock),
                if (hiddenCount > 0)
                  TextButton.icon(
                    onPressed: onOpenClock,
                    icon: const Icon(Icons.list_alt),
                    label: Text('还有 $hiddenCount 项，查看全部'),
                  ),
              ],
            ),
    );
  }
}

class _SeniorReminderOccurrence {
  const _SeniorReminderOccurrence(this.reminder, this.occurrence);

  final ReminderData reminder;
  final DateTime occurrence;
}

class _SeniorReminderTask extends StatelessWidget {
  const _SeniorReminderTask({
    required this.item,
    required this.onTakeMedicine,
    required this.onAcknowledge,
    required this.onOpenClock,
  });

  final _SeniorReminderOccurrence item;
  final Future<void> Function(ReminderData, DateTime) onTakeMedicine;
  final Future<void> Function(ReminderData, DateTime) onAcknowledge;
  final VoidCallback onOpenClock;

  @override
  Widget build(BuildContext context) {
    final reminder = item.reminder;
    final overdue = item.occurrence.isBefore(DateTime.now());
    final dose = reminder.payload['dose']?.toString().trim() ?? '';
    final instructions =
        reminder.payload['instructions']?.toString().trim() ?? '';
    final detail =
        [dose, instructions].where((value) => value.isNotEmpty).join('，');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: overdue && reminder.type == 'medicine'
            ? Colors.orange.withValues(alpha: 0.08)
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('HH:mm').format(item.occurrence),
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.deepBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.displayLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (detail.isNotEmpty) Text(detail),
                    Text(
                      overdue && reminder.type == 'medicine' ? '尚未确认' : '待完成',
                      style: TextStyle(
                        color: overdue && reminder.type == 'medicine'
                            ? Colors.orange.shade800
                            : AppTheme.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => reminder.type == 'medicine'
                      ? onTakeMedicine(reminder, item.occurrence)
                      : onAcknowledge(reminder, item.occurrence),
                  child: Text(reminder.type == 'medicine' ? '已服' : '知道了'),
                ),
              ),
              if (reminder.type == 'medicine') ...[
                const SizedBox(width: 10),
                TextButton(onPressed: onOpenClock, child: const Text('更多操作')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SeniorPlanTask extends StatelessWidget {
  const _SeniorPlanTask({required this.plan, required this.onTap});

  final PlanRecordData plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      leading: Icon(
        plan.type == 'exercise'
            ? Icons.directions_walk_outlined
            : Icons.restaurant_outlined,
        size: 30,
        color: AppTheme.deepBlue,
      ),
      title: Text(
        plan.label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(plan.summary.isEmpty ? '今天的健康计划' : plan.summary),
      trailing: FilledButton(onPressed: onTap, child: const Text('去完成')),
    );
  }
}

class _SeniorMetrics extends StatelessWidget {
  const _SeniorMetrics({required this.data, required this.onRecord});

  final HealthDashboardData? data;
  final ValueChanged<String?> onRecord;

  @override
  Widget build(BuildContext context) {
    const types = [
      ('bp', '血压', Icons.favorite_outline),
      ('glucose', '血糖', Icons.water_drop_outlined),
      ('weight', '体重', Icons.scale_outlined),
      ('spo2', '血氧', Icons.air_outlined),
    ];
    return _Panel(
      title: '常用健康数据',
      child: Column(
        children: [
          for (final type in types)
            _SeniorMetricRow(
              label: type.$2,
              icon: type.$3,
              entry: data?.latestIndicator(type.$1),
              onTap: () => onRecord(type.$1),
            ),
        ],
      ),
    );
  }
}

class _SeniorMetricRow extends StatelessWidget {
  const _SeniorMetricRow({
    required this.label,
    required this.icon,
    required this.entry,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final HealthIndicatorEntry? entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final abnormal = entry != null &&
        HealthSafety.isAbnormalIndicator(entry!.type, entry!.payload);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28, color: AppTheme.deepBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  entry?.displayValue ?? '尚未记录',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                ),
                if (entry != null)
                  Text(
                    '${DateFormat('MM/dd HH:mm').format(entry!.measuredTime)}${abnormal ? '　超出参考范围' : ''}',
                    style: TextStyle(
                      color: abnormal ? Colors.orange.shade800 : AppTheme.muted,
                      fontWeight:
                          abnormal ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(onPressed: onTap, child: const Text('重新记录')),
        ],
      ),
    );
  }
}

class _SeniorQuickRecord extends StatelessWidget {
  const _SeniorQuickRecord({required this.onRecord});

  final ValueChanged<String?> onRecord;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '快速记录',
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.25,
        children: [
          _SeniorQuickButton(
              '测血压', Icons.favorite_outline, () => onRecord('bp')),
          _SeniorQuickButton(
              '测血糖', Icons.water_drop_outlined, () => onRecord('glucose')),
          _SeniorQuickButton(
              '记体重', Icons.scale_outlined, () => onRecord('weight')),
          _SeniorQuickButton(
              '其他记录', Icons.add_chart_outlined, () => onRecord(null)),
        ],
      ),
    );
  }
}

class _SeniorQuickButton extends StatelessWidget {
  const _SeniorQuickButton(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label, textAlign: TextAlign.center),
    );
  }
}

class _HealthAlertCard extends StatelessWidget {
  const _HealthAlertCard({required this.alert, required this.onRecord});

  final HealthTrendAlert alert;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final color =
        alert.isCritical ? Colors.red.shade700 : Colors.orange.shade800;
    final actionText = alert.isCritical
        ? '立即就医'
        : alert.type == 'bp'
            ? '30分钟后复测'
            : '次日复测';
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              alert.isCritical
                  ? Icons.warning_amber_rounded
                  : Icons.monitor_heart_outlined,
              color: color,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: TextStyle(
                      color: color,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(alert.message),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: alert.isCritical ? null : onRecord,
                    icon: Icon(alert.isCritical
                        ? Icons.local_hospital_outlined
                        : Icons.add_chart_outlined),
                    label: Text(actionText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.surfaceContainerLow, colors.surfaceContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
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
