import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/paywall.dart';
import '../../core/network/ai_api.dart';

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final AiApi _aiApi = sl<AiApi>();

  bool _loading = true;
  bool _aiGenerating = false;
  String _selectedProvider = 'deepseek';
  UserProfileData? _profile;
  List<PlanRecordData> _plans = const [];
  PlanRecordData? _riskPlan;
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
    final plans = await _repo.loadPlans(limit: 40);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      final riskList = plans.where((p) => p.type == 'risk').toList();
      _riskPlan = riskList.isEmpty ? null : riskList.first;
      _plans = plans.where((p) => p.type != 'risk').toList();
      _loading = false;
    });
  }

  Future<void> _generate() async {
    final messenger = ScaffoldMessenger.of(context);
    await _repo.generateWeeklyPlan();
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('本地计划已更新')));
  }

  Future<void> _generateWithAi() async {
    // 1. 账号 + 会员校验
    if (!mounted) return;
    final ok = await requireAccountAndMember(context, PaywallFeature.aiPlan);
    if (!ok) return;

    // 2. 弹出模型选择对话框
    final provider = await _showProviderPicker();
    if (provider == null || !mounted) return;
    setState(() {
      _aiGenerating = true;
      _selectedProvider = provider;
    });

    try {
      // 3. 拉取最近指标
      final indicators = await _repo.loadIndicators(limit: 20);

      // 4. 调用 AI
      final result = await _aiApi.generatePlan(
        profile: _profile ?? UserProfileData.empty(),
        recentIndicators: indicators,
        provider: provider,
        goal: _profile?.goal ?? 'general',
      );

      if (!mounted) return;

      // 5. 展示 AI 方案（底部弹窗）
      await _showAiPlanSheet(result);
    } catch (e) {
      if (!mounted) return;
      await _ensureLocalPlanAfterAiFailure();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _aiGenerating = false);
    }
  }

  Future<void> _ensureLocalPlanAfterAiFailure() async {
    if (_plans.isNotEmpty) return;
    try {
      await _repo.generateWeeklyPlan();
      await _load(silent: true);
    } catch (_) {}
  }

  Future<String?> _showProviderPicker() {
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择 AI 模型',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('方案质量因模型而异，可切换尝试',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 16),
            for (final p in [
              ('deepseek', '🤖', 'DeepSeek', '推理能力强，方案逻辑严密'),
              ('doubao', '🫘', '豆包（火山方舟）', '中文表达自然，建议贴近生活'),
              ('qwen', '🌟', '通义千问', '医疗健康垂直训练，参考价值高'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(p.$2, style: const TextStyle(fontSize: 24)),
                title: Text(p.$3,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(p.$4,
                    style:
                        const TextStyle(color: AppTheme.muted, fontSize: 12)),
                trailing: _selectedProvider == p.$1
                    ? const Icon(Icons.check_circle,
                        color: AppTheme.deepBlue, size: 20)
                    : null,
                onTap: () => Navigator.pop(context, p.$1),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAiPlanSheet(AiPlanResult result) async {
    final parsed = _parseAiPlanJson(result.rawJson);

    final summary = parsed['summary'] as String? ?? '方案已生成';
    final keyFocus = parsed['keyFocus'] as String? ?? '';
    final riskAlert = parsed['riskAlert'] as String?;
    final targetCal = _intValue(parsed['targetCalories']);
    final days = _mapList(parsed['days']);
    final rawFallback = days.isEmpty ? _cleanAiText(result.rawJson) : '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // 把手
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              // 标题行
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const Icon(Icons.psychology_outlined,
                      color: AppTheme.deepBlue, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('AI 健康方案',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.pageBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: Text(result.provider,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.muted)),
                  ),
                ]),
              ),
              const SizedBox(height: 4),
              // 概要
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary,
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 13)),
                    if (keyFocus.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.flag_outlined,
                            size: 14, color: AppTheme.deepBlue),
                        const SizedBox(width: 4),
                        Text('本周重点：$keyFocus',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.deepBlue,
                                fontWeight: FontWeight.w600)),
                        if (targetCal != null) ...[
                          const SizedBox(width: 12),
                          Text('目标 $targetCal kcal/天',
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.muted)),
                        ],
                      ]),
                    ],
                    if (riskAlert != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(children: [
                          Icon(Icons.warning_amber_outlined,
                              size: 14, color: Colors.orange.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(riskAlert,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade700)),
                          ),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 20),
              // 7天内容
              Expanded(
                child: days.isEmpty
                    ? SingleChildScrollView(
                        controller: ctrl,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
                        child: _RawAiPlanCard(text: rawFallback),
                      )
                    : ListView.separated(
                        controller: ctrl,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
                        itemCount: days.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _AiDayCard(day: days[i]),
                      ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        context.push('/chat');
                      },
                      icon: const Icon(Icons.chat_outlined, size: 16),
                      label: const Text('继续对话'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: days.isEmpty
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(context);
                              try {
                                await _repo.applyAiPlan(
                                  plan: parsed,
                                  provider: result.provider,
                                );
                                if (mounted) {
                                  await _load(silent: true);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: const Text('AI 方案已应用到打卡任务'),
                                      action: SnackBarAction(
                                        label: '去打卡',
                                        onPressed: () => context.push('/clock'),
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(content: Text('应用失败：$e')),
                                );
                              }
                            },
                      icon: const Icon(Icons.sync, size: 16),
                      label: Text(days.isEmpty ? '无法应用' : '应用方案'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _parseAiPlanJson(String rawJson) {
    final raw = rawJson.trim();
    if (raw.isEmpty) return <String, dynamic>{};

    final candidates = <String>[raw];
    final firstBrace = raw.indexOf('{');
    final lastBrace = raw.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      candidates.add(raw.substring(firstBrace, lastBrace + 1));
    }

    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry('$key', value));
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  String _cleanAiText(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      final start = text.indexOf('\n');
      final end = text.lastIndexOf('```');
      if (start >= 0 && end > start) {
        text = text.substring(start + 1, end).trim();
      }
    }
    return text.isEmpty ? '方案生成完成，但未返回可解析内容。请重试。' : text;
  }

  List<Map<String, dynamic>> _mapList(Object? raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry('$key', value)))
        .toList();
  }

  int? _intValue(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  String _friendlyError(Object e) {
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map) {
        final code = (body['code'] as num?)?.toInt() ?? 0;
        final message = (body['message'] ?? body['msg'])?.toString();
        if (code == 40301) return 'AI 方案生成需要会员权益，请先开通或续费。';
        if (code == 42901) return '今日 AI 使用次数已达上限，明日 0 点重置。';
        if (code == 40101) return 'AI 服务密钥失效，请联系管理员检查后台配置。';
        if (code == 50301) {
          return 'AI 服务暂时繁忙，已为你保留本地规则计划，稍后可重试。';
        }
        if (message != null && message.isNotEmpty) return message;
      }
      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return 'AI 响应较慢已超时，已为你保留本地规则计划，稍后可重试。';
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        return '无法连接 AI 服务，请检查手机和后端是否在同一 WiFi。';
      }
    }
    final s = e.toString();
    if (s.contains('40301')) return '会员权益已过期，请续费';
    if (s.contains('50301')) return 'AI 服务暂时繁忙，已为你保留本地规则计划，稍后可重试。';
    if (s.contains('Connection') || s.contains('Socket')) {
      return '网络连接失败，请检查后端服务和 WiFi。';
    }
    return 'AI 生成暂时不可用，已为你保留本地规则计划。';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final grouped = _groupPlans();
    final riskPayload = _riskPlan?.payload;
    final targetKcal = riskPayload?['targetKcal'] as int? ?? 0;
    final bottomPadding = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
        children: [
          _PlanHero(
            profile: _profile,
            riskPlan: _riskPlan,
            targetKcal: targetKcal,
            onGenerate: _generate,
            onAiGenerate: _generateWithAi,
            aiGenerating: _aiGenerating,
          ),
          const SizedBox(height: 16),
          if (_riskPlan != null) ...[
            _RiskCard(plan: _riskPlan!),
            const SizedBox(height: 16),
          ],
          _Panel(
            title: '计划筛选',
            subtitle: '按类型查看当前 7 天规划',
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
                _FilterChip(
                  label: '测量',
                  selected: _filter == 'measurement',
                  onTap: () => setState(() => _filter = 'measurement'),
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
    required this.riskPlan,
    required this.targetKcal,
    required this.onGenerate,
    this.onAiGenerate,
    this.aiGenerating = false,
  });

  final UserProfileData? profile;
  final PlanRecordData? riskPlan;
  final int targetKcal;
  final VoidCallback onGenerate;
  final VoidCallback? onAiGenerate;
  final bool aiGenerating;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final bmi = profile?.bmi ?? 0;
    final goalNote = riskPlan?.payload['goalNote'] as String? ?? '';
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
              const Text('7 天健康规划',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                profile == null
                    ? '先完善档案，系统会基于 BMI、指标和目标生成个性化建议。'
                    : (goalNote.isNotEmpty
                        ? goalNote
                        : '基于档案生成，每日约 $targetKcal kcal，低盐低脂高纤维。'),
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
                  _InfoPill(
                      label: '热量',
                      value: targetKcal == 0 ? '--' : '$targetKcal kcal'),
                  _InfoPill(label: '状态', value: profile?.bmiLevel ?? '待完善'),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: onGenerate,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                    label: const Text('本地生成'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          AppTheme.deepBlue.withValues(alpha: 0.15),
                      foregroundColor: AppTheme.deepBlue,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: aiGenerating ? null : onAiGenerate,
                    icon: aiGenerating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.psychology_outlined, size: 16),
                    label: Text(aiGenerating ? 'AI 生成中…' : 'AI 智能生成 ⚜'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0277BD),
                    ),
                  ),
                ],
              ),
            ],
          );

          final rulesBox = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.pageBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('生成规则', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 10),
                Text('· 风险评估 → 确定热量 → 饮食原则',
                    style: TextStyle(color: AppTheme.muted, height: 1.5)),
                Text('· 运动强度：有氧 + 力量 + 恢复轮替',
                    style: TextStyle(color: AppTheme.muted, height: 1.5)),
                Text('· 7 天饮食 / 运动 / 测量计划全覆盖',
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
                    Expanded(flex: 2, child: rulesBox),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summary,
                    const SizedBox(height: 16),
                    rulesBox,
                  ],
                );
        },
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.plan});

  final PlanRecordData plan;

  @override
  Widget build(BuildContext context) {
    final risks = (plan.payload['risks'] as List?)?.cast<String>() ?? [];
    final summary = plan.payload['summary'] as String? ?? '';
    final dietNote = plan.payload['dietNote'] as String? ?? '';
    final hasRisk = risks.isNotEmpty;

    // 零风险：轻量摘要条
    if (!hasRisk) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FFF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 16, color: Color(0xFF16A34A)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                summary.isNotEmpty ? summary : '各项已录入指标均在正常范围。',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF15803D), height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    // 有风险：醒目卡片
    final hasSevere = risks.any(
        (r) => r.contains('危象') || r.contains('糖尿病标准') || r.contains('危险偏低'));
    final cardColor =
        hasSevere ? const Color(0xFFFEE2E2) : const Color(0xFFFFFBEB);
    final borderColor =
        hasSevere ? const Color(0xFFFCA5A5) : const Color(0xFFFCD34D);
    final iconColor =
        hasSevere ? const Color(0xFFB91C1C) : const Color(0xFF92400E);
    final icon = hasSevere ? Icons.error_outline : Icons.warning_amber_outlined;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 7),
            Text('指标提示',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: iconColor)),
          ]),
          const SizedBox(height: 8),
          Text(summary,
              style: TextStyle(fontSize: 13, color: iconColor, height: 1.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: risks
                .map((r) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(r,
                          style: TextStyle(
                              fontSize: 11,
                              color: iconColor,
                              fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
          if (dietNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('饮食建议：$dietNote',
                style: TextStyle(fontSize: 12, color: iconColor, height: 1.5)),
          ],
        ],
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
    final measurements =
        plans.where((item) => item.type == 'measurement').toList();

    final showMeal = filter == 'all' || filter == 'meal';
    final showExercise = filter == 'all' || filter == 'exercise';
    final showMeasure = filter == 'all' || filter == 'measurement';

    final visibleCount = (showMeal ? meals.length : 0) +
        (showExercise ? exercises.length : 0) +
        (showMeasure ? measurements.length : 0);

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
        subtitle: Text('$visibleCount 条计划',
            style: const TextStyle(color: AppTheme.muted)),
        children: [
          if (showMeal) _MealDetailSection(items: meals),
          if (showExercise)
            _PlanSection(
              title: '运动计划',
              icon: Icons.directions_run_outlined,
              items: exercises,
            ),
          if (showMeasure) _MeasurementSection(items: measurements),
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

class _MealDetailSection extends StatelessWidget {
  const _MealDetailSection({required this.items});

  final List<PlanRecordData> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

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
              children: const [
                Icon(Icons.restaurant_outlined,
                    size: 18, color: AppTheme.deepBlue),
                SizedBox(width: 8),
                Text('饮食计划', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            for (final item in items) ...[
              if (item.summary.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(item.summary,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.deepBlue, height: 1.4)),
                ),
              _MealRow(
                icon: Icons.wb_sunny_outlined,
                label: '早餐',
                items: _castList(item.payload['breakfast']),
              ),
              _MealRow(
                icon: Icons.lunch_dining_outlined,
                label: '午餐',
                items: _castList(item.payload['lunch']),
              ),
              _MealRow(
                icon: Icons.nightlight_outlined,
                label: '晚餐',
                items: _castList(item.payload['dinner']),
              ),
              _MealRow(
                icon: Icons.apple_outlined,
                label: '加餐',
                items: _castList(item.payload['snack']),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _castList(Object? raw) {
    if (raw is List) return raw.cast<String>();
    return const [];
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({
    required this.icon,
    required this.label,
    required this.items,
  });

  final IconData icon;
  final String label;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppTheme.muted),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(items.join('  /  '),
                style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _MeasurementSection extends StatelessWidget {
  const _MeasurementSection({required this.items});

  final List<PlanRecordData> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final allItems = <String>[];
    for (final plan in items) {
      final list = plan.payload['items'];
      if (list is List) allItems.addAll(list.cast<String>());
    }
    if (allItems.isEmpty) return const SizedBox.shrink();

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
              children: const [
                Icon(Icons.monitor_heart_outlined,
                    size: 18, color: AppTheme.deepBlue),
                SizedBox(width: 8),
                Text('每日测量', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            for (final text in allItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('·  ',
                        style: TextStyle(
                            color: AppTheme.deepBlue,
                            fontWeight: FontWeight.w700)),
                    Expanded(
                      child: Text(text,
                          style: const TextStyle(
                              color: AppTheme.muted, height: 1.5)),
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

// ── AI 方案每日卡片 ───────────────────────────────────────────

class _AiDayCard extends StatelessWidget {
  const _AiDayCard({required this.day});
  final Map<String, dynamic> day;

  @override
  Widget build(BuildContext context) {
    final weekDay = day['weekDay'] as String? ?? '';
    final diet = _asMap(day['diet']);
    final exercise = _asMap(day['exercise']);
    final reminders =
        (day['reminders'] as List?)?.map((item) => '$item').toList() ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF0277BD),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(weekDay,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          if (diet.isNotEmpty) ...[
            const _SectionRow(
                Icons.restaurant_outlined, '饮食', Color(0xFF0277BD)),
            const SizedBox(height: 6),
            for (final label in ['早餐', '午餐', '晚餐', '加餐'])
              if (diet[_dietKey(label)] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(label,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.muted,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: Text('${diet[_dietKey(label)]}',
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ]),
                ),
          ],
          if (exercise.isNotEmpty) ...[
            const SizedBox(height: 10),
            const _SectionRow(
                Icons.directions_run_outlined, '运动', Colors.green),
            const SizedBox(height: 6),
            Text(
              '${exercise['type'] ?? ''} · '
              '${exercise['durationMinutes'] ?? 0}分钟 · '
              '${exercise['intensity'] ?? ''}',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.muted,
                  fontWeight: FontWeight.w600),
            ),
            if (exercise['description'] != null) ...[
              const SizedBox(height: 4),
              Text('${exercise['description']}',
                  style: const TextStyle(fontSize: 13)),
            ],
          ],
          if (reminders.isNotEmpty) ...[
            const SizedBox(height: 10),
            const _SectionRow(
                Icons.notifications_outlined, '提醒', Colors.orange),
            const SizedBox(height: 6),
            for (final r in reminders)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(children: [
                  const Icon(Icons.circle, size: 5, color: AppTheme.muted),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(r, style: const TextStyle(fontSize: 13))),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  static String _dietKey(String label) => switch (label) {
        '早餐' => 'breakfast',
        '午餐' => 'lunch',
        '晚餐' => 'dinner',
        _ => 'snack',
      };
}

class _SectionRow extends StatelessWidget {
  const _SectionRow(this.icon, this.label, this.color);
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

class _RawAiPlanCard extends StatelessWidget {
  const _RawAiPlanCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '原始方案',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(height: 1.55, fontSize: 13)),
          const SizedBox(height: 10),
          const Text(
            '当前内容无法解析为应用可执行任务，可重试生成。',
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, val) => MapEntry('$key', val));
  return <String, dynamic>{};
}
