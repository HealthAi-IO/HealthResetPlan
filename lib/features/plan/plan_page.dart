import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  final HealthRepository _repo = sl<HealthRepository>();

  bool _loading = true;
  UserProfileData? _profile;
  List<PlanRecordData> _plans = const [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _onRepoChanged() {
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() => _loading = true);
    }
    final profile = await _repo.loadProfile();
    final plans = await _repo.loadPlans(limit: 30);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _plans = plans;
      _loading = false;
    });
  }

  Future<void> _generate() async {
    final messenger = ScaffoldMessenger.of(context);
    await _repo.generateWeeklyPlan();
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('本地计划已更新')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final grouped = _groupPlans();
    final bmi = _profile?.bmi ?? 0;
    final calories = bmi >= 28
        ? 1500
        : bmi >= 24
            ? 1700
            : 1900;
    final bottomPadding =
        MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
        children: [
          _PlanHero(
            profile: _profile,
            calories: calories,
            bmi: bmi,
            onGenerate: _generate,
          ),
          const SizedBox(height: 16),
          _Panel(
            title: '计划筛选',
            subtitle: '按类型查看当前 7 天游程',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FilterChip(
                  label: '全部',
                  selected: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                _FilterChip(
                  label: '饮食',
                  selected: _filter == 'meal',
                  onTap: () => setState(() => _filter = 'meal'),
                ),
                _FilterChip(
                  label: '运动',
                  selected: _filter == 'exercise',
                  onTap: () => setState(() => _filter = 'exercise'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (grouped.isEmpty)
            const _EmptyState(
              icon: Icons.event_note_outlined,
              text: '暂无本地计划。点击上方按钮即可生成 7 天饮食与运动计划。',
            )
          else
            ...grouped.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DayPlanCard(
                  date: entry.key,
                  plans: entry.value,
                  filter: _filter,
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Map<String, List<PlanRecordData>> _groupPlans() {
    final map = <String, List<PlanRecordData>>{};
    for (final plan in _plans) {
      if (_filter != 'all' && plan.type != _filter) continue;
      final key = DateFormat('yyyy-MM-dd').format(plan.date);
      map.putIfAbsent(key, () => []).add(plan);
    }
    return map;
  }
}

class _PlanHero extends StatelessWidget {
  const _PlanHero({
    required this.profile,
    required this.calories,
    required this.bmi,
    required this.onGenerate,
  });

  final UserProfileData? profile;
  final int calories;
  final double bmi;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary.withValues(alpha: 0.12), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('本地 7 天游程',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                profile == null
                    ? '先完善档案，系统会基于 BMI 和最近指标生成建议。'
                    : '当前建议热量约 $calories kcal / 天，重点保持低盐、低脂、高纤维。',
                style: const TextStyle(color: AppTheme.muted, height: 1.5),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _InfoPill(
                      label: 'BMI',
                      value: bmi == 0 ? '--' : bmi.toStringAsFixed(1)),
                  _InfoPill(label: '热量', value: '$calories kcal'),
                  _InfoPill(label: '状态', value: profile?.bmiLevel ?? '待完善'),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('生成 / 刷新计划'),
              ),
            ],
          );

          final guidance = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.pageBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本地生成规则', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 10),
                Text('· 饮食优先低盐低脂，补充优质蛋白。',
                    style: TextStyle(color: AppTheme.muted, height: 1.5)),
                Text('· 运动安排有氧 + 力量 + 恢复，避免过载。',
                    style: TextStyle(color: AppTheme.muted, height: 1.5)),
                Text('· 用药和称重可在打卡页同步配置。',
                    style: TextStyle(color: AppTheme.muted, height: 1.5)),
              ],
            ),
          );

          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: summary),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: guidance),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summary,
                    const SizedBox(height: 16),
                    guidance,
                  ],
                );
        },
      ),
    );
  }
}

class _DayPlanCard extends StatelessWidget {
  const _DayPlanCard({
    required this.date,
    required this.plans,
    required this.filter,
  });

  final String date;
  final List<PlanRecordData> plans;
  final String filter;

  @override
  Widget build(BuildContext context) {
    final displayDate =
        DateFormat('MM月dd日').format(DateFormat('yyyy-MM-dd').parse(date));
    final meals = plans.where((item) => item.type == 'meal').toList();
    final exercises = plans.where((item) => item.type == 'exercise').toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        title: Text(displayDate,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${plans.length} 条计划',
            style: const TextStyle(color: AppTheme.muted)),
        children: [
          if (filter != 'exercise')
            _PlanSection(
              title: '饮食计划',
              icon: Icons.restaurant_outlined,
              items: meals,
            ),
          if (filter != 'meal')
            _PlanSection(
              title: '运动计划',
              icon: Icons.directions_run_outlined,
              items: exercises,
            ),
        ],
      ),
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<PlanRecordData> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.pageBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.deepBlue),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            for (final item in items) ...[
              Text(
                item.summary,
                style: const TextStyle(color: AppTheme.muted, height: 1.5),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.deepBlue,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: Colors.white,
      selectedColor: AppTheme.deepBlue,
      side: const BorderSide(color: AppTheme.cardBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label · $value',
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppTheme.deepBlue),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
