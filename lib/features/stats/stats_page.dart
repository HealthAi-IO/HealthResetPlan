import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_settings_controller.dart';
import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/membership_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_api.dart';

ImageProvider<Object>? _authenticatedAvatarProvider(AccountInfo? info) {
  if (info == null || info.avatarUrl.isEmpty) return null;
  final objectKey = Uri.tryParse(info.avatarUrl)?.queryParameters['objectKey'];
  final token = UserSession.instance.accessToken;
  if (objectKey == null || objectKey.isEmpty || token == null) return null;
  final baseUrl =
      sl<ApiClient>().dio.options.baseUrl.replaceFirst(RegExp(r'/$'), '');
  return NetworkImage(
    '$baseUrl/files/content?objectKey=${Uri.encodeQueryComponent(objectKey)}'
    '&contentType=image%2Fjpeg',
    headers: {'Authorization': 'Bearer $token'},
  );
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, this.onOpenClock});

  final VoidCallback? onOpenClock;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final HealthRepository _repo = sl<HealthRepository>();

  bool _loading = true;
  HealthDashboardData? _data;
  ClockStats? _clockStats;
  String? _error;

  List<HealthIndicatorEntry> _weightEntries = const [];
  List<HealthIndicatorEntry> _bpEntries = const [];
  List<HealthIndicatorEntry> _glucoseEntries = const [];
  List<HealthIndicatorEntry> _spo2Entries = const [];
  String _seniorMetric = 'bp';

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

  void _openClock() {
    final onOpenClock = widget.onOpenClock;
    if (onOpenClock != null) {
      onOpenClock();
      return;
    }
    context.go('/clock');
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final futures = <Future<Object?>>[
        _repo.loadDashboard(),
        _repo.loadClockStats(),
        _repo.loadIndicators(type: 'weight', limit: 20),
        _repo.loadIndicators(type: 'bp', limit: 20),
        _repo.loadIndicators(type: 'glucose', limit: 20),
        _repo.loadIndicators(type: 'spo2', limit: 20),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _data = results[0] as HealthDashboardData;
        _clockStats = results[1] as ClockStats;
        _weightEntries =
            (results[2] as List<HealthIndicatorEntry>).reversed.toList();
        _bpEntries =
            (results[3] as List<HealthIndicatorEntry>).reversed.toList();
        _glucoseEntries =
            (results[4] as List<HealthIndicatorEntry>).reversed.toList();
        _spo2Entries =
            (results[5] as List<HealthIndicatorEntry>).reversed.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _StatsLoadingView();

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('加载失败，下拉刷新重试', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final data = _data;
    if (data == null) return const Center(child: CircularProgressIndicator());
    final profile = data.profile;
    final bmi = profile?.bmi ?? 0;
    final bottomPad = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    void pushInput(String type) {
      context.push('/indicators/input', extra: type).then((_) {
        if (mounted) _load(silent: true);
      });
    }

    if (appSettingsController.seniorMode) {
      final entries = switch (_seniorMetric) {
        'weight' => _weightEntries,
        'glucose' => _glucoseEntries,
        'spo2' => _spo2Entries,
        _ => _bpEntries,
      };
      return _SeniorStatsView(
        data: data,
        metric: _seniorMetric,
        entries: entries,
        clockStats: _clockStats,
        onSelectMetric: (value) => setState(() => _seniorMetric = value),
        onRecord: () => pushInput(_seniorMetric),
        onMore: () => context.push('/indicators').then((_) {
          if (mounted) _load(silent: true);
        }),
        onClock: _openClock,
        onRefresh: () => _load(silent: true),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const PageStorageKey('stats-scroll'),
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
        cacheExtent: 900,
        children: [
          _TrendHeader(
            profile: profile,
            onEditProfile: () => context.push('/profile'),
          ),
          const SizedBox(height: 14),
          _SummaryRow(profile: profile, data: data),
          const SizedBox(height: 14),
          _Panel(
            title: '打卡完成率',
            subtitle: '日 / 周 / 月三档统计',
            trailing: TextButton.icon(
              onPressed: _openClock,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('去打卡'),
            ),
            child: _ClockRateSection(stats: _clockStats),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: '体重趋势',
            subtitle: '最新 ${_weightEntries.length} 项  单位：kg  · 触摸查看数据',
            trailing: _AddButton(onTap: () => pushInput('weight')),
            child: _weightEntries.isEmpty
                ? _EmptyChart(
                    text: '暂无体重记录，点击 + 开始录入',
                    onAdd: () => pushInput('weight'),
                  )
                : _WeightChart(entries: _weightEntries),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: '血压趋势',
            subtitle: '收缩压（红）/ 舒张压（蓝）mmHg  · 触摸查看数据',
            trailing: _AddButton(onTap: () => pushInput('bp')),
            child: _bpEntries.isEmpty
                ? _EmptyChart(
                    text: '暂无血压记录，点击 + 开始录入',
                    onAdd: () => pushInput('bp'),
                  )
                : _BpChart(entries: _bpEntries),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: '血糖趋势',
            subtitle: '空腹 / 餐后  单位：mmol/L  · 触摸查看数据',
            trailing: _AddButton(onTap: () => pushInput('glucose')),
            child: _glucoseEntries.isEmpty
                ? _EmptyChart(
                    text: '暂无血糖记录，点击 + 开始录入',
                    onAdd: () => pushInput('glucose'),
                  )
                : _GlucoseChart(entries: _glucoseEntries),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: '最近指标',
            subtitle: '最新 6 项，点全部查看完整记录',
            trailing: TextButton.icon(
              onPressed: () => context.push('/indicators').then((_) {
                if (mounted) _load(silent: true);
              }),
              icon: const Icon(Icons.list_alt_outlined, size: 16),
              label: const Text('全部'),
            ),
            child: _RecentIndicators(
              items: data.indicators,
              bmi: bmi,
              onAdd: () => pushInput('weight'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _SeniorStatsView extends StatelessWidget {
  const _SeniorStatsView({
    required this.data,
    required this.metric,
    required this.entries,
    required this.clockStats,
    required this.onSelectMetric,
    required this.onRecord,
    required this.onMore,
    required this.onClock,
    required this.onRefresh,
  });

  final HealthDashboardData data;
  final String metric;
  final List<HealthIndicatorEntry> entries;
  final ClockStats? clockStats;
  final ValueChanged<String> onSelectMetric;
  final VoidCallback onRecord;
  final VoidCallback onMore;
  final VoidCallback onClock;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 7));
    final visibleEntries =
        entries.where((entry) => entry.measuredTime.isAfter(cutoff)).toList();
    final latest = entries.lastOrNull;
    final abnormal = latest != null &&
        HealthSafety.isAbnormalIndicator(latest.type, latest.payload);
    final critical = latest != null &&
        HealthSafety.isCriticalIndicator(latest.type, latest.payload);
    final stateColor = critical
        ? Theme.of(context).colorScheme.error
        : abnormal
            ? AppTheme.warning(context)
            : AppTheme.success(context);
    final bottomPad = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('senior-stats-scroll'),
        padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPad),
        children: [
          const Text('健康变化',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            '一次查看一个指标，更容易看清变化',
            style: TextStyle(fontSize: 17, color: AppTheme.muted),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in const [
                ('bp', '血压', Icons.favorite_outline),
                ('glucose', '血糖', Icons.water_drop_outlined),
                ('weight', '体重', Icons.scale_outlined),
                ('spo2', '血氧', Icons.air_outlined),
              ])
                ChoiceChip(
                  selected: metric == item.$1,
                  onSelected: (_) => onSelectMetric(item.$1),
                  avatar: Icon(item.$3, size: 21),
                  label: Text(item.$2),
                  labelStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: latest == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_seniorMetricLabel(metric)}还没有记录',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: onRecord,
                        icon: const Icon(Icons.add),
                        label: const Text('记录第一次测量'),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '最新${latest.label}',
                              style: TextStyle(
                                  fontSize: 18, color: AppTheme.muted),
                            ),
                          ),
                          Row(
                            children: [
                              Icon(
                                critical
                                    ? Icons.warning_amber_rounded
                                    : abnormal
                                        ? Icons.info_outline
                                        : Icons.check_circle_outline,
                                color: stateColor,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                critical
                                    ? '明显异常'
                                    : abnormal
                                        ? '需要留意'
                                        : '正常',
                                style: TextStyle(
                                  color: stateColor,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        latest.displayValue,
                        style: TextStyle(
                          color: critical || abnormal
                              ? stateColor
                              : AppTheme.deepBlue,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '测量时间 ${DateFormat('MM月dd日 HH:mm').format(latest.measuredTime)}',
                        style: TextStyle(fontSize: 16, color: AppTheme.muted),
                      ),
                      if (abnormal) ...[
                        const SizedBox(height: 12),
                        Text(
                          critical
                              ? '如同时感到不适，请及时联系医生或就医。'
                              : '建议按平时方式复测，并继续观察变化。',
                          style: const TextStyle(fontSize: 16, height: 1.45),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: onRecord,
                        icon: const Icon(Icons.add),
                        label: const Text('记录新的测量'),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最近 7 天${_seniorMetricLabel(metric)}趋势',
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text('触摸折线可查看具体测量时间', style: TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 16),
                if (visibleEntries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(child: Text('最近 7 天暂无记录')),
                  )
                else
                  _SeniorMetricChart(metric: metric, entries: visibleEntries),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onMore,
            icon: const Icon(Icons.list_alt_outlined),
            label: const Text('查看更多健康指标'),
          ),
          if (clockStats != null) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                title: const Text('查看打卡统计',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                trailing: const Icon(Icons.expand_more),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Column(
                      children: [
                        _ClockRateSection(stats: clockStats),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: onClock,
                          child: const Text('前往打卡页'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeniorMetricChart extends StatelessWidget {
  const _SeniorMetricChart({required this.metric, required this.entries});

  final String metric;
  final List<HealthIndicatorEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (metric == 'bp') return _BpChart(entries: entries);
    if (metric == 'glucose') return _GlucoseChart(entries: entries);
    if (metric == 'weight') return _WeightChart(entries: entries);
    final values = entries
        .map((entry) => (entry.payload['spo2Pct'] as num?)?.toDouble() ?? 0)
        .toList();
    return _TouchableLineChart(
      seriesList: [_Series(values: values, color: AppTheme.water(context))],
      axisLabels: _trendAxisLabels(entries),
      tooltipLabels: _trendTooltipLabels(entries),
      unit: '%',
    );
  }
}

String _seniorMetricLabel(String type) => switch (type) {
      'bp' => '血压',
      'glucose' => '血糖',
      'weight' => '体重',
      'spo2' => '血氧',
      _ => '健康指标',
    };

class _StatsLoadingView extends StatelessWidget {
  const _StatsLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _StatsSkeletonBlock(height: 156),
        SizedBox(height: 14),
        _StatsSkeletonBlock(height: 96),
        SizedBox(height: 14),
        _StatsSkeletonBlock(height: 220),
      ],
    );
  }
}

class _StatsSkeletonBlock extends StatelessWidget {
  const _StatsSkeletonBlock({required this.height});

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

// ── 账号状态卡片 ──────────────────────────────────────────────
class _TrendHeader extends StatelessWidget {
  const _TrendHeader({
    required this.profile,
    required this.onEditProfile,
  });

  final UserProfileData? profile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    final displayName = (profile?.nickname.isNotEmpty == true)
        ? profile!.nickname
        : UserSession.instance.name;
    final name = displayName.isNotEmpty ? displayName : '健康趋势';
    final age = profile?.age;
    final ageText = age == null || age == 0 ? '-- 岁' : '$age 岁';
    final bmi = profile?.bmi ?? 0;
    final bmiText = bmi == 0 ? 'BMI --' : 'BMI ${bmi.toStringAsFixed(1)}';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: Colors.white24,
                child: Text(
                  name.characters.first,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: onEditProfile,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('编辑'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '查看已记录指标的变化与完成情况',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      _MiniStatusChip(text: ageText),
                      _MiniStatusChip(text: bmiText)
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStatusChip extends StatelessWidget {
  const _MiniStatusChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ignore: unused_element
class _CombinedProfileCard extends StatelessWidget {
  const _CombinedProfileCard({
    required this.accountInfo,
    required this.memberStatus,
    required this.profile,
    required this.onAvatarTap,
    required this.onLogin,
    required this.onMembership,
    required this.onSignOut,
    required this.onEditProfile,
  });

  final AccountInfo? accountInfo;
  final MembershipStatus memberStatus;
  final UserProfileData? profile;
  final VoidCallback onAvatarTap;
  final VoidCallback onLogin;
  final VoidCallback onMembership;
  final VoidCallback onSignOut;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    final isLoggedIn = UserSession.instance.isAccountLogin;
    final displayName = (profile?.nickname.isNotEmpty == true)
        ? profile!.nickname
        : UserSession.instance.name;
    final safeName = displayName.isNotEmpty ? displayName : '未设置昵称';
    final imageUrl = _avatarImageUrl(accountInfo);
    final membershipLabel = '免费使用';
    final age = profile?.age;
    final ageText = age == null || age == 0 ? '-- 岁' : '$age 岁';
    final bmi = profile?.bmi ?? 0;
    final bmiText = bmi == 0 ? 'BMI --' : 'BMI ${bmi.toStringAsFixed(1)}';
    const cloudText = '自动保存';
    final initials = safeName.characters.first;
    final phoneTail = accountInfo?.phoneTail.trim() ?? '';
    // ignore: unused_local_variable
    final phoneText = phoneTail.isEmpty ? '手机号未绑定' : '手机号 **** $phoneTail';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: isLoggedIn ? onAvatarTap : null,
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white24,
                  foregroundImage: imageUrl,
                  child: imageUrl == null
                      ? Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoggedIn ? '已绑定账号' : '本地免费版',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isLoggedIn ? safeName : '数据保存在本机，可随时绑定账号',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _CardBadge(text: membershipLabel),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            safeName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: onEditProfile,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('编辑'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$ageText   $bmiText',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _CardInfoPill(
                  icon: Icons.cloud_outlined,
                  label: '账号数据',
                  value: cloudText,
                  highlight: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CardInfoPill(
                  icon: Icons.verified_user_outlined,
                  label: '使用状态',
                  value: membershipLabel,
                  highlight: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!isLoggedIn)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('注册 / 登录账号'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('免费使用中'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white60),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('退出登录'),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ),
          ],
        ],
      ),
    );
  }

  ImageProvider<Object>? _avatarImageUrl(AccountInfo? info) =>
      _authenticatedAvatarProvider(info);
}

class _CardBadge extends StatelessWidget {
  const _CardBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CardInfoPill extends StatelessWidget {
  const _CardInfoPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.highlight,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: highlight
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AccountStatusCard extends StatelessWidget {
  const _AccountStatusCard({
    required this.accountInfo,
    required this.memberStatus,
    required this.profile,
    required this.onAvatarTap,
    required this.onLogin,
    required this.onMembership,
    required this.onSignOut,
    required this.onEditProfile,
  });

  final AccountInfo? accountInfo;
  final MembershipStatus memberStatus;
  final UserProfileData? profile;
  final VoidCallback onAvatarTap;
  final VoidCallback onLogin;
  final VoidCallback onMembership;
  final VoidCallback onSignOut;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    final isLoggedIn = UserSession.instance.isAccountLogin;
    final displayName = (profile?.nickname.isNotEmpty == true)
        ? profile!.nickname
        : UserSession.instance.name;
    final imageUrl = _avatarImageUrl(accountInfo);
    final membershipLabel = memberStatus.isActive
        ? (memberStatus.planName ?? '已开启')
        : memberStatus.isExpired
            ? '已过期，当前免费版'
            : '免费版';
    final ageText = profile?.age == 0 ? '--' : '${profile?.age ?? '--'} 岁';
    final bmiText = (profile == null || profile.bmi == 0)
        ? 'BMI --'
        : 'BMI ${profile.bmi.toStringAsFixed(1)}';
    final gradient = AppTheme.accentGradient(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GestureDetector(
              onTap: isLoggedIn ? onAvatarTap : null,
              child: CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white24,
                foregroundImage: imageUrl,
                child: imageUrl == null
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName.characters.first
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoggedIn ? '已绑定账号' : '本地免费版',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayName.isNotEmpty ? displayName : '未设置昵称',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                membershipLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white24,
                child: Text(
                  displayName.isNotEmpty ? displayName.characters.first : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.isNotEmpty ? displayName : '未设置昵称',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$ageText   $bmiText',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onEditProfile,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('编辑'),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (!isLoggedIn) ...[
            const Text(
              '登录账号后可使用健康记录与 AI 等在线能力。',
              style:
                  TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('注册 / 登录账号'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ] else ...[
            _AccountDetailRow(
              icon: Icons.cloud_outlined,
              label: '账号数据',
              value: '自动保存',
              valueColor: Colors.lightGreenAccent,
            ),
            const SizedBox(height: 6),
            _AccountDetailRow(
              icon: Icons.verified_user,
              label: '使用状态',
              value: membershipLabel,
              valueColor: Colors.lightGreenAccent,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('免费使用中'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('退出登录'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  ImageProvider<Object>? _avatarImageUrl(AccountInfo? info) =>
      _authenticatedAvatarProvider(info);
}

// ignore: unused_element
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.accountInfo,
    required this.memberStatus,
    required this.profile,
    required this.onAvatarTap,
    required this.onLogin,
    required this.onMembership,
    required this.onSignOut,
  });

  final AccountInfo? accountInfo;
  final MembershipStatus memberStatus;
  final UserProfileData? profile;
  final VoidCallback onAvatarTap;
  final VoidCallback onLogin;
  final VoidCallback onMembership;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = UserSession.instance.isAccountLogin;
    final displayName = (profile?.nickname.isNotEmpty == true)
        ? profile!.nickname
        : UserSession.instance.name;
    final imageUrl = _avatarImageUrl(accountInfo);
    // ignore: unused_local_variable
    final membershipLabel = memberStatus.isActive
        ? (memberStatus.planName ?? '已开启')
        : memberStatus.isExpired
            ? '已过期，当前免费版'
            : '免费版';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GestureDetector(
              onTap: isLoggedIn ? onAvatarTap : null,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white24,
                    foregroundImage: imageUrl,
                    child: imageUrl == null
                        ? Text(
                            displayName.isNotEmpty
                                ? displayName.characters.first
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                  ),
                  if (isLoggedIn)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: Icon(
                          Icons.camera_alt_outlined,
                          size: 11,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoggedIn ? '已绑定账号' : '尚未绑定账号',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (isLoggedIn && displayName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (isLoggedIn)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.lightGreenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text('在线',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
          const SizedBox(height: 10),
          if (!isLoggedIn) ...[
            const Text(
              '注册或登录账号后即可使用健康记录与 AI 等在线能力。',
              style:
                  TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('注册 / 登录账号'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ] else ...[
            // 已登录：展示账号详情
            _AccountDetailRow(
              icon: Icons.person_outline,
              label: '昵称',
              value: displayName.isNotEmpty ? displayName : '未设置',
            ),
            const SizedBox(height: 6),
            _AccountDetailRow(
              icon: Icons.cloud_outlined,
              label: '账号数据',
              value: '自动保存',
              valueColor: Colors.lightGreenAccent,
            ),
            const SizedBox(height: 6),
            _AccountDetailRow(
              icon: Icons.verified_user,
              label: '使用状态',
              value: '免费使用',
              valueColor: Colors.lightGreenAccent,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('免费使用中'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  ImageProvider<Object>? _avatarImageUrl(AccountInfo? info) =>
      _authenticatedAvatarProvider(info);
}

class _AccountDetailRow extends StatelessWidget {
  const _AccountDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: Colors.white60),
      const SizedBox(width: 8),
      Text('$label：',
          style: const TextStyle(color: Colors.white60, fontSize: 13)),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

// ── 用户卡片 ──────────────────────────────────────────────────
// ignore: unused_element
class _UserCard extends StatelessWidget {
  const _UserCard({required this.profile, required this.onEditProfile});
  final UserProfileData? profile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    final name = (profile?.nickname.isNotEmpty == true)
        ? profile!.nickname
        : UserSession.instance.name;
    final bmi = profile?.bmi ?? 0;
    final age = (profile != null && profile.birthYear > 0)
        ? '${DateTime.now().year - profile.birthYear} 岁'
        : '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: Colors.white24,
          child: Text(
            name.isNotEmpty ? name.characters.first : '?',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isNotEmpty ? name : '未设置名称',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Row(children: [
            if (age.isNotEmpty) ...[
              Text(age,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(width: 10),
            ],
            if (bmi > 0)
              Text('BMI ${bmi.toStringAsFixed(1)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ])),
        TextButton.icon(
          onPressed: onEditProfile,
          icon:
              const Icon(Icons.edit_outlined, size: 15, color: Colors.white70),
          label: const Text('编辑',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ),
      ]),
    );
  }
}

// ── 概要卡片行 ────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.profile, required this.data});
  final UserProfileData? profile;
  final HealthDashboardData data;

  @override
  Widget build(BuildContext context) {
    final bmi = profile?.bmi ?? 0;
    final latestWeight = data.latestIndicator('weight');
    final latestBp = data.latestIndicator('bp');
    final todayPct = (data.todayCompletion * 100).round();

    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth >= 600 ? 4 : 2;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: cols == 4 ? 1.6 : 1.5,
        children: [
          _SummaryCard(
              title: 'BMI',
              value: bmi == 0 ? '--' : bmi.toStringAsFixed(1),
              sub: profile?.bmiLevel ?? '待完善',
              color: Theme.of(context).colorScheme.secondary),
          _SummaryCard(
              title: '最新体重',
              value: latestWeight?.displayValue ?? '--',
              sub: latestWeight == null
                  ? ''
                  : DateFormat('MM/dd HH:mm').format(latestWeight.measuredTime),
              color: AppTheme.weight(context)),
          _SummaryCard(
              title: '最新血压',
              value: latestBp?.displayValue ?? '--',
              sub: latestBp == null
                  ? ''
                  : DateFormat('MM/dd HH:mm').format(latestBp.measuredTime),
              color: Theme.of(context).colorScheme.error),
          _SummaryCard(
              title: '今日完成',
              value: '$todayPct%',
              sub: '${data.todayClockCount} 条打卡',
              color: AppTheme.warning(context)),
        ],
      );
    });
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.title,
      required this.value,
      required this.sub,
      required this.color});
  final String title;
  final String value;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            if (sub.isNotEmpty)
              Text(sub, style: TextStyle(color: AppTheme.muted, fontSize: 11)),
          ]),
    );
  }
}

// ── 打卡完成率 ────────────────────────────────────────────────
class _ClockRateSection extends StatefulWidget {
  const _ClockRateSection({required this.stats});
  final ClockStats? stats;

  @override
  State<_ClockRateSection> createState() => _ClockRateSectionState();
}

class _ClockRateSectionState extends State<_ClockRateSection> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    if (stats == null) {
      return const SizedBox(
          height: 60, child: Center(child: CircularProgressIndicator()));
    }

    final labels = ['今日', '本周', '本月'];
    final rates = [stats.todayRate, stats.weekRate, stats.monthRate];
    final counts = [stats.today, stats.week, stats.month];
    final days = [stats.todayDays, stats.weekDays, stats.monthDays];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: _tab == i
                      ? AppTheme.deepBlue
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                      color: _tab == i ? Colors.white : AppTheme.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    )),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 14),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey(_tab),
          child: _RateBar(
              rate: rates[_tab], counts: counts[_tab], days: days[_tab]),
        ),
      ),
    ]);
  }
}

class _RateBar extends StatelessWidget {
  const _RateBar(
      {required this.rate, required this.counts, required this.days});
  final double rate;
  final Map<String, int> counts;
  final int days;

  @override
  Widget build(BuildContext context) {
    final pct = (rate * 100).round();
    final typeInfos = [
      ('meal', '饮食', AppTheme.meal(context)),
      ('exercise', '运动', AppTheme.exercise(context)),
      ('medicine', '用药', AppTheme.medicine(context)),
      ('weight', '称重', AppTheme.weight(context)),
      ('water', '饮水', AppTheme.water(context)),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 12,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                rate >= 0.8
                    ? AppTheme.success(context)
                    : rate >= 0.5
                        ? AppTheme.warning(context)
                        : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('$pct%',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in typeInfos)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: t.$3.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.$3.withValues(alpha: 0.3)),
            ),
            child: Text('${t.$2} ${counts[t.$1] ?? 0} 次',
                style: TextStyle(
                    color: t.$3, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
      ]),
      const SizedBox(height: 4),
      Text('统计周期 $days 天',
          style: TextStyle(color: AppTheme.muted, fontSize: 11)),
    ]);
  }
}

// ── 体重图表 ─────────────────────────────────────────────────
List<String> _trendAxisLabels(List<HealthIndicatorEntry> entries) {
  final counts = <String, int>{};
  for (final entry in entries) {
    final day = DateFormat('yyyy-MM-dd').format(entry.measuredTime);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return entries.map((entry) {
    final day = DateFormat('yyyy-MM-dd').format(entry.measuredTime);
    return DateFormat(counts[day]! > 1 ? 'HH:mm' : 'MM/dd')
        .format(entry.measuredTime);
  }).toList();
}

List<String> _trendTooltipLabels(List<HealthIndicatorEntry> entries) => entries
    .map((entry) => DateFormat('MM/dd HH:mm').format(entry.measuredTime))
    .toList();

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.entries});
  final List<HealthIndicatorEntry> entries;

  @override
  Widget build(BuildContext context) {
    final values = entries
        .map((e) => (e.payload['weightKg'] as num?)?.toDouble() ?? 0)
        .toList();
    return _TouchableLineChart(
      seriesList: [_Series(values: values, color: AppTheme.weight(context))],
      axisLabels: _trendAxisLabels(entries),
      tooltipLabels: _trendTooltipLabels(entries),
      unit: 'kg',
    );
  }
}

// ── 血压双线图 ────────────────────────────────────────────────
class _BpChart extends StatelessWidget {
  const _BpChart({required this.entries});
  final List<HealthIndicatorEntry> entries;

  @override
  Widget build(BuildContext context) {
    final systolic = entries
        .map((e) => (e.payload['systolic'] as num?)?.toDouble() ?? 0)
        .toList();
    final diastolic = entries
        .map((e) => (e.payload['diastolic'] as num?)?.toDouble() ?? 0)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _TouchableLineChart(
        seriesList: [
          _Series(
              values: systolic,
              color: Theme.of(context).colorScheme.error,
              label: '收缩压'),
          _Series(
              values: diastolic,
              color: Theme.of(context).colorScheme.secondary,
              label: '舒张压'),
        ],
        axisLabels: _trendAxisLabels(entries),
        tooltipLabels: _trendTooltipLabels(entries),
        unit: 'mmHg',
      ),
      const SizedBox(height: 8),
      Row(children: [
        _Legend(color: Theme.of(context).colorScheme.error, label: '收缩压'),
        const SizedBox(width: 16),
        _Legend(color: Theme.of(context).colorScheme.secondary, label: '舒张压'),
      ]),
      const SizedBox(height: 4),
      Text('正常参考：收缩压 <140  舒张压 <90 mmHg',
          style: TextStyle(color: AppTheme.muted, fontSize: 11)),
    ]);
  }
}

// ── 血糖折线图 ────────────────────────────────────────────────
class _GlucoseChart extends StatelessWidget {
  const _GlucoseChart({required this.entries});
  final List<HealthIndicatorEntry> entries;

  @override
  Widget build(BuildContext context) {
    final values = entries
        .map((e) => (e.payload['glucoseMmol'] as num?)?.toDouble() ?? 0)
        .toList();
    final mealTypes = entries
        .map((e) => e.payload['mealType'] as String? ?? 'fasting')
        .toList();
    final fasting =
        entries.where((e) => (e.payload['mealType'] as String?) != 'postmeal');
    final fastingAvg = fasting.isEmpty
        ? 0.0
        : fasting
                .map((e) => (e.payload['glucoseMmol'] as num?)?.toDouble() ?? 0)
                .reduce((a, b) => a + b) /
            fasting.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _TouchableLineChart(
        seriesList: [_Series(values: values, color: AppTheme.warning(context))],
        axisLabels: _trendAxisLabels(entries),
        tooltipLabels: _trendTooltipLabels(entries),
        unit: 'mmol/L',
        tooltipExtras: mealTypes
            .map((t) => t == 'postmeal'
                ? '餐后2h'
                : t == 'random'
                    ? '随机'
                    : '空腹')
            .toList(),
      ),
      const SizedBox(height: 8),
      Row(children: [
        _Legend(color: AppTheme.warning(context), label: '血糖'),
        if (fastingAvg > 0) ...[
          const SizedBox(width: 12),
          Text('空腹均值 ${fastingAvg.toStringAsFixed(1)} mmol/L',
              style: TextStyle(color: AppTheme.muted, fontSize: 12)),
        ],
      ]),
      const SizedBox(height: 4),
      Text('正常参考：空腹 3.9-6.1  餐后2h <7.8 mmol/L',
          style: TextStyle(color: AppTheme.muted, fontSize: 11)),
    ]);
  }
}

// ── 可触摸折线图 ──────────────────────────────────────────────
class _TouchableLineChart extends StatefulWidget {
  const _TouchableLineChart({
    required this.seriesList,
    required this.axisLabels,
    required this.tooltipLabels,
    required this.unit,
    this.tooltipExtras,
  });

  final List<_Series> seriesList;
  final List<String> axisLabels;
  final List<String> tooltipLabels;
  final String unit;
  final List<String>? tooltipExtras;

  @override
  State<_TouchableLineChart> createState() => _TouchableLineChartState();
}

class _TouchableLineChartState extends State<_TouchableLineChart> {
  int? _selectedIndex;

  static const _padL = 44.0;
  static const _padR = 10.0;

  void _handleTouch(Offset pos) {
    final size = context.size;
    if (size == null) return;
    final n =
        widget.seriesList.isEmpty ? 0 : widget.seriesList.first.values.length;
    if (n == 0) return;
    final w = size.width - _padL - _padR;
    int closest = 0;
    double minDist = double.infinity;
    for (var i = 0; i < n; i++) {
      final dx = _padL + w * (n == 1 ? 0.5 : i / (n - 1));
      final dist = (dx - pos.dx).abs();
      if (dist < minDist) {
        minDist = dist;
        closest = i;
      }
    }
    if (_selectedIndex != closest) setState(() => _selectedIndex = closest);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _handleTouch(d.localPosition),
      onPanUpdate: (d) => _handleTouch(d.localPosition),
      child: SizedBox(
        height: 200,
        child: LayoutBuilder(builder: (_, constraints) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                painter: _LineChartPainter(
                  seriesList: widget.seriesList,
                  dates: widget.axisLabels,
                  unit: widget.unit,
                  selectedIndex: _selectedIndex,
                ),
                size: constraints.biggest,
              ),
              if (_selectedIndex != null)
                _buildTooltip(constraints.maxWidth, _selectedIndex!),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTooltip(double chartWidth, int idx) {
    if (widget.seriesList.isEmpty) return const SizedBox.shrink();
    final n = widget.seriesList.first.values.length;
    final w = chartWidth - _padL - _padR;
    final dx = _padL + w * (n == 1 ? 0.5 : idx / (n - 1));
    const tooltipW = 118.0;
    final left = (dx - tooltipW / 2).clamp(0.0, chartWidth - tooltipW);
    final date =
        idx < widget.tooltipLabels.length ? widget.tooltipLabels[idx] : '';
    final extra =
        widget.tooltipExtras != null && idx < widget.tooltipExtras!.length
            ? widget.tooltipExtras![idx]
            : null;

    return Positioned(
      left: left,
      top: 2,
      width: tooltipW,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          boxShadow: [
            BoxShadow(
                color: Theme.of(context)
                    .colorScheme
                    .shadow
                    .withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(date,
                  style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              if (extra != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(extra,
                      style: TextStyle(color: AppTheme.muted, fontSize: 10)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            for (final s in widget.seriesList)
              if (idx < s.values.length && s.values[idx] > 0)
                Text(
                  s.label.isEmpty
                      ? '${_fmtVal(s.values[idx])} ${widget.unit}'
                      : '${s.label} ${_fmtVal(s.values[idx])}',
                  style: TextStyle(
                      color: s.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 14),
                ),
          ],
        ),
      ),
    );
  }

  String _fmtVal(double v) =>
      v > 50 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 14, height: 3, color: color),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    ]);
  }
}

// ── 通用折线图 Painter ────────────────────────────────────────
class _Series {
  const _Series({required this.values, required this.color, this.label = ''});
  final List<double> values;
  final Color color;
  final String label;
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({
    required this.seriesList,
    required this.dates,
    required this.unit,
    this.selectedIndex,
  });
  final List<_Series> seriesList;
  final List<String> dates;
  final String unit;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (seriesList.isEmpty) return;
    final longest = seriesList.map((s) => s.values.length).reduce(max);
    if (longest == 0) return;

    const padL = 44.0, padR = 10.0, padT = 12.0, padB = 28.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    if (w <= 0 || h <= 0) return;

    final allVals =
        seriesList.expand((s) => s.values).where((v) => v > 0).toList();
    if (allVals.isEmpty) return;
    final minV = allVals.reduce(min);
    final maxV = allVals.reduce(max);
    final span = (maxV - minV) < 0.5 ? 2.0 : (maxV - minV) * 1.15;
    final base = max(0.0, minV - span * 0.05);

    final gridPaint = Paint()
      ..color = AppTheme.cardBorder
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: AppTheme.muted, fontSize: 10);

    for (var i = 0; i <= 4; i++) {
      final dy = padT + h - h * i / 4;
      canvas.drawLine(Offset(padL, dy), Offset(padL + w, dy), gridPaint);
      final val = base + span * i / 4;
      final tp = TextPainter(
        text: TextSpan(
            text: val.toStringAsFixed(val > 50 ? 0 : 1), style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padL - tp.width - 4, dy - tp.height / 2));
    }

    Offset ptFor(List<double> values, int i) {
      final n = values.length;
      final dx = padL + w * (n == 1 ? 0.5 : i / (n - 1));
      final v = values[i];
      final dy =
          v <= 0 ? padT + h : padT + h - ((v - base) / span * h).clamp(0.0, h);
      return Offset(dx, dy);
    }

    for (final series in seriesList) {
      final n = series.values.length;
      if (n == 0) continue;

      final linePaint = Paint()
        ..color = series.color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final fillPaint = Paint()
        ..color = series.color.withValues(alpha: 0.07)
        ..style = PaintingStyle.fill;
      final dotPaint = Paint()
        ..color = series.color
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(ptFor(series.values, 0).dx, ptFor(series.values, 0).dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(ptFor(series.values, i).dx, ptFor(series.values, i).dy);
      }
      canvas.drawPath(path, linePaint);

      final first = ptFor(series.values, 0);
      final last = ptFor(series.values, n - 1);
      final area = Path()
        ..moveTo(first.dx, padT + h)
        ..lineTo(first.dx, first.dy);
      for (var i = 1; i < n; i++) {
        area.lineTo(ptFor(series.values, i).dx, ptFor(series.values, i).dy);
      }
      area
        ..lineTo(last.dx, padT + h)
        ..close();
      canvas.drawPath(area, fillPaint);

      for (var i = 0; i < n; i++) {
        canvas.drawCircle(ptFor(series.values, i), 3.2, dotPaint);
      }
    }

    // 选中点高亮
    if (selectedIndex != null) {
      final si = selectedIndex!;
      final n = longest;
      if (si < n) {
        final dx = padL + w * (n == 1 ? 0.5 : si / (n - 1));
        canvas.drawLine(
          Offset(dx, padT),
          Offset(dx, padT + h),
          Paint()
            ..color = AppTheme.muted.withValues(alpha: 0.28)
            ..strokeWidth = 1.5,
        );
        for (final series in seriesList) {
          if (si >= series.values.length || series.values[si] <= 0) continue;
          final p = ptFor(series.values, si);
          canvas.drawCircle(
              p,
              6.5,
              Paint()
                ..color = Colors.white
                ..style = PaintingStyle.fill);
          canvas.drawCircle(
              p,
              6.5,
              Paint()
                ..color = series.color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.5);
        }
      }
    }

    final n = longest;
    final step = max(1, (n / 5).ceil());
    for (var i = 0; i < n; i += step) {
      if (i >= dates.length) break;
      final dx = padL + w * (n == 1 ? 0.5 : i / (n - 1));
      final tp = TextPainter(
        text: TextSpan(text: dates[i], style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(dx - tp.width / 2, padT + h + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.selectedIndex != selectedIndex ||
      old.seriesList.length != seriesList.length ||
      (seriesList.isNotEmpty &&
          old.seriesList.isNotEmpty &&
          seriesList.first.values.length != old.seriesList.first.values.length);
}

// ── 空图提示 ──────────────────────────────────────────────────
class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.text, required this.onAdd});
  final String text;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(text,
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('立即录入')),
      ]),
    );
  }
}

// ── 最近指标列表 ──────────────────────────────────────────────
class _RecentIndicators extends StatelessWidget {
  const _RecentIndicators(
      {required this.items, required this.bmi, required this.onAdd});
  final List<HealthIndicatorEntry> items;
  final double bmi;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Column(children: [
        Text('暂无数据', style: TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 8),
        TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('录入指标')),
      ]);
    }
    return Column(children: [
      for (final item in items.take(6))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(item.type),
                    color: AppTheme.deepBlue, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(item.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(item.displayValue,
                        style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                  ])),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '测量 ${DateFormat('MM/dd HH:mm').format(item.measuredTime)}',
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                  if (item.updatedAt > item.createdAt)
                    Text(
                      '修改 ${DateFormat('MM/dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.updatedAt))}',
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ]),
          ),
        ),
    ]);
  }
}

// ── 面板容器 ──────────────────────────────────────────────────
class _Panel extends StatelessWidget {
  const _Panel(
      {required this.title,
      required this.subtitle,
      required this.child,
      this.trailing});
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                Text(subtitle,
                    style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              ])),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(Icons.add_circle_outline, color: AppTheme.deepBlue),
      tooltip: '录入',
    );
  }
}

IconData _iconFor(String type) => switch (type) {
      'bp' => Icons.favorite_outline,
      'weight' => Icons.scale_outlined,
      'glucose' => Icons.water_drop_outlined,
      'lipid' => Icons.science_outlined,
      'heart_rate' => Icons.monitor_heart_outlined,
      _ => Icons.fiber_manual_record_outlined,
    };
