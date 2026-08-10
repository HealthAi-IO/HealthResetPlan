import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_router.dart';
import '../../app/app_settings_controller.dart';
import '../../app/app_theme.dart';
import '../../core/ai/ai_plan_generation_controller.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/paywall.dart';
import '../../core/network/ai_api.dart';
import '../../core/network/telemetry_api.dart';
import '../../core/notification/reminder_consent.dart';
import '../../core/notification/reminder_scheduler.dart';
import '../../core/privacy/ai_consent_gate.dart';
import '../../core/widgets/ai_content_notice.dart';
import '../../core/widgets/health_ui.dart';

const _aiDoctorDisclaimer = 'AI 不能代替医生诊断，只提供健康管理建议；如有异常或症状加重，请及时就医。';

bool _isAiPlanProvider(String provider) =>
    provider.isNotEmpty && provider != 'local' && provider != 'manual';

String _planProviderLabel(String provider) => switch (provider) {
      'doubao' => '豆包',
      'qwen' => '通义千问',
      'glm' => '智谱 GLM',
      'deepseek' => 'DeepSeek',
      _ => 'AI',
    };

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final AiApi _aiApi = sl<AiApi>();
  final AiPlanGenerationController _aiPlanController =
      sl<AiPlanGenerationController>();
  final ReminderScheduler _reminderScheduler = sl<ReminderScheduler>();

  bool _loading = true;
  bool _presentingAiResult = false;
  String _selectedProvider = 'qwen';
  UserProfileData? _profile;
  List<PlanRecordData> _plans = const [];
  List<ClockRecordData> _clockRecords = const [];
  PlanRecordData? _riskPlan;
  String _filter = 'all';
  int? _aiRemaining;
  int _handledAiEventId = 0;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _aiPlanController.addListener(_onAiPlanGenerationChanged);
    _load();
    _loadAiUsage();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _onAiPlanGenerationChanged());
  }

  Future<void> _loadAiUsage() async {
    try {
      final usage = await _aiApi.dailyUsage();
      if (mounted) setState(() => _aiRemaining = usage['plan']);
    } catch (_) {}
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _aiPlanController.removeListener(_onAiPlanGenerationChanged);
    super.dispose();
  }

  void _onAiPlanGenerationChanged() {
    if (!mounted) return;
    setState(() {});
    if (AppRouter.router.routeInformationProvider.value.uri.path != '/plan') {
      return;
    }
    if (_aiPlanController.eventId == _handledAiEventId) return;
    _handledAiEventId = _aiPlanController.eventId;
    if (_aiPlanController.status == AiPlanGenerationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _presentAiResult());
    } else if (_aiPlanController.status == AiPlanGenerationStatus.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleAiFailure());
    }
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
    final clockRecords = await _repo.loadClockRecords(limit: 40);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      final riskList = plans.where((p) => p.type == 'risk').toList();
      _riskPlan = riskList.isEmpty ? null : riskList.first;
      final isCritical = _isCriticalRiskPlan(_riskPlan);
      _plans =
          isCritical ? const [] : plans.where((p) => p.type != 'risk').toList();
      _clockRecords = clockRecords;
      _loading = false;
    });
  }

  Future<void> _generate() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_profile == null ||
        !_profile!.isComplete ||
        _profile!.gender == 'unknown') {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('请先完善性别、出生年份、身高和体重，再生成基础计划'),
          action: SnackBarAction(
              label: '去完善', onPressed: () => context.push('/profile')),
        ),
      );
      return;
    }
    if (!await _confirmReplacePlans()) return;
    try {
      await _repo.generateWeeklyPlan();
      sl<TelemetryApi>().record('plan_generated');
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('已根据你的档案生成基础计划')));
    } on PlanBlockedException catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        messenger
            .showSnackBar(const SnackBar(content: Text('计划生成失败，请检查档案后重试')));
      }
    }
  }

  Future<bool> _confirmReplacePlans() async {
    if (_plans.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('替换现有计划吗？'),
            content: const Text('新的 7 天计划会替换当前计划。已经完成的打卡记录会保留。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('返回'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认替换'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _generateWithAi() async {
    // 1. 登录校验：所有登录用户均可使用 AI 能力。
    if (!mounted) return;
    if (_profile == null ||
        !_profile!.isComplete ||
        _profile!.gender == 'unknown') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先完善性别、出生年份、身高和体重，再生成个性化 AI 计划'),
          action: SnackBarAction(
              label: '去完善', onPressed: () => context.push('/profile')),
        ),
      );
      return;
    }
    try {
      await _repo.ensurePlanEligible(_profile);
    } on PlanBlockedException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    if (!mounted) return;
    if (!await ensureAiConsent(context)) return;
    if (!mounted) return;
    final ok = await requireAccountAndMember(context, PaywallFeature.aiPlan);
    if (!ok) return;

    // 2. 弹出模型选择对话框
    final provider = await _showProviderPicker();
    if (provider == null || !mounted) return;
    setState(() => _selectedProvider = provider);
    _aiPlanController.start(profile: _profile!, provider: provider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI 已开始生成计划，你可以继续使用其他功能')),
    );
  }

  Future<void> _presentAiResult() async {
    if (!mounted || _presentingAiResult) return;
    final result = _aiPlanController.result;
    if (result == null) return;
    _presentingAiResult = true;
    final hasExecutablePlan =
        _mapList(_parseAiPlanJson(result.rawJson)['days']).length == 7;
    try {
      await _showAiPlanSheet(result);
      sl<TelemetryApi>().record('plan_generated');
      _loadAiUsage();
    } finally {
      _presentingAiResult = false;
      if (!hasExecutablePlan) _aiPlanController.clear();
    }
  }

  Future<void> _handleAiFailure() async {
    final error = _aiPlanController.error;
    await _ensureLocalPlanAfterAiFailure();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_friendlyError(error ?? 'AI 生成失败')),
        backgroundColor: Colors.orange.shade700,
      ),
    );
    _aiPlanController.clear();
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
              ('doubao', '🫘', '豆包 Seed 2.1 Pro', '响应更快，适合生成 7 天计划'),
              ('qwen', '🌟', '通义千问 3.7 Plus', '默认模型，支持健康计划生成'),
              ('glm', 'GLM', '智谱 GLM-5.2', '适合结构化健康计划生成'),
              ('deepseek', '🤖', 'DeepSeek V4 Pro', '推理能力强，方案逻辑严密'),
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
    final hasExecutablePlan = days.length == 7;
    final invalidMessage =
        hasExecutablePlan ? '' : _invalidAiPlanMessage(result.rawJson);

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
                    child: Text(_planProviderLabel(result.provider),
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
                    const AiContentNotice(feature: 'AI健康方案'),
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 8),
                    const _AiDisclaimerCard(),
                  ],
                ),
              ),
              const Divider(height: 20),
              // 7天内容
              Expanded(
                child: !hasExecutablePlan
                    ? SingleChildScrollView(
                        controller: ctrl,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
                        child: _InvalidAiPlanCard(message: invalidMessage),
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
                      onPressed: !hasExecutablePlan
                          ? null
                          : () async {
                              if (!await _confirmReplacePlans()) return;
                              if (!mounted) return;
                              final reminderConsent = await confirmReminderUse(
                                context,
                                _reminderScheduler,
                              );
                              if (!mounted) return;
                              final createReminders = reminderConsent ==
                                  ReminderConsentResult.allowed;
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(context);
                              try {
                                await _repo.applyAiPlan(
                                  plan: parsed,
                                  provider: result.provider,
                                  createReminders: createReminders,
                                );
                                if (createReminders) {
                                  await _reminderScheduler.syncAll();
                                }
                                if (mounted) {
                                  _aiPlanController.clear();
                                  await _load(silent: true);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        createReminders
                                            ? 'AI 方案和计划提醒已应用'
                                            : 'AI 方案已应用，未开启计划提醒',
                                      ),
                                      action: SnackBarAction(
                                        label: '去打卡',
                                        onPressed: () =>
                                            AppRouter.router.go('/clock'),
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
                      label: Text(!hasExecutablePlan ? '无法应用' : '应用方案'),
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
        if (decoded is Map<String, dynamic>) return _normalizePlanMap(decoded);
        if (decoded is Map) {
          return _normalizePlanMap(
            decoded.map((key, value) => MapEntry('$key', value)),
          );
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _normalizePlanMap(Map<String, dynamic> map) {
    if (map['days'] is List) return map;

    for (final key in const ['plan', 'data', 'result', 'weeklyPlan']) {
      final nested = map[key];
      if (nested is Map<String, dynamic>) return _normalizePlanMap(nested);
      if (nested is Map) {
        return _normalizePlanMap(
          nested.map((k, v) => MapEntry('$k', v)),
        );
      }
    }

    for (final key in const ['rawJson', 'content', 'text']) {
      final nested = map[key];
      if (nested is String && nested.trim().isNotEmpty) {
        final parsed = _parseAiPlanJson(nested);
        if (parsed['days'] is List) return parsed;
      }
    }

    return map;
  }

  String _invalidAiPlanMessage(String raw) {
    final text = _cleanAiText(raw);
    if (text.contains('"days"') && !text.trimRight().endsWith('}')) {
      return 'AI 返回内容被截断，未形成完整 7 天方案。请重新生成，或手动切换其他模型。';
    }
    return 'AI 返回格式不完整，未能转换为可执行的 7 天打卡任务。请重新生成，或切换模型。';
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
        if (code == 40301) return '请先登录账号后再生成 AI 方案。';
        if (code == 42901) return '今日 AI 使用次数已达上限，明日 0 点重置。';
        if (code == 42902) return 'AI 服务暂时繁忙，请稍后再试。';
        if (code == 40101) return 'AI 服务密钥失效，请联系管理员检查后台配置。';
        if (code == 50302) {
          return '当前模型返回的计划格式异常，自动修复后仍未通过，请稍后重试或切换模型。';
        }
        if (code == 50301) {
          return '当前 AI 模型暂时不可用，已为你保留本地规则计划，请稍后重试。';
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
    if (s.contains('40301')) return '请先登录账号后再试';
    if (s.contains('50302')) {
      return '当前模型返回的计划格式异常，自动修复后仍未通过，请稍后重试或切换模型。';
    }
    if (s.contains('50301')) {
      return '当前 AI 模型暂时不可用，已为你保留本地规则计划，请稍后重试。';
    }
    if (s.contains('Connection') || s.contains('Socket')) {
      return '网络连接失败，请检查后端服务和 WiFi。';
    }
    return 'AI 生成暂时不可用，已为你保留本地规则计划。';
  }

  Future<void> _showSeniorPlanTools() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '调整计划',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                '重新生成会先让你确认，不会静默覆盖现有计划。',
                style: TextStyle(color: AppTheme.muted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _aiPlanController.isGenerating
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _generateWithAi();
                      },
                icon: const Icon(Icons.psychology_outlined),
                label: Text(_aiPlanController.isGenerating
                    ? 'AI 正在生成'
                    : 'AI 智能生成 7 天计划'),
              ),
              if (_aiRemaining != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '今天还可使用 $_aiRemaining 次',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _generate();
                },
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('按本地规则生成 7 天计划'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _editPlan(date: DateTime.now());
                },
                icon: const Icon(Icons.add),
                label: const Text('手动添加今天的计划'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _PlanLoadingView();
    }

    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final grouped = Map<String, List<PlanRecordData>>.fromEntries(
      _groupPlans().entries.where((entry) => entry.key == todayKey),
    );
    final bottomPadding = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    if (appSettingsController.seniorMode) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayPlans = _plans.where((plan) {
        final date = plan.date;
        return DateTime(date.year, date.month, date.day) == today;
      }).toList();
      final futurePlans = _plans.where((plan) {
        final date = plan.date;
        return DateTime(date.year, date.month, date.day).isAfter(today);
      }).toList();
      final todayRecords = _clockRecords.where((record) {
        final date = record.clockTime;
        return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day &&
            record.status == 'done';
      }).toList();
      return _SeniorPlanView(
        todayPlans: todayPlans,
        futurePlans: futurePlans,
        doneTypes: todayRecords.map((record) => record.type).toSet(),
        riskPlan: _riskPlan,
        onGoClock: () => context.go('/clock'),
        onAdjust: _showSeniorPlanTools,
        onEdit: _editPlan,
        onRefresh: () => _load(silent: true),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const PageStorageKey('plan-scroll'),
        padding: EdgeInsets.fromLTRB(20, 4, 20, bottomPadding),
        cacheExtent: 900,
        children: [
          HealthPageHeader(
            title: '健康计划',
            subtitle: '把下一步行动安排清楚',
            action: PopupMenuButton<String>(
              tooltip: '添加计划',
              icon: const Icon(Icons.add),
              onSelected: (value) {
                switch (value) {
                  case 'ai':
                    if (_aiPlanController.status ==
                        AiPlanGenerationStatus.completed) {
                      _presentAiResult();
                    } else {
                      _generateWithAi();
                    }
                    break;
                  case 'local':
                    _generate();
                    break;
                  case 'manual':
                    _editPlan(date: DateTime.now());
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'ai',
                  enabled: !_aiPlanController.isGenerating,
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppTheme.aiPurple),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _aiPlanController.isGenerating
                              ? 'AI 生成中…'
                              : _aiPlanController.status ==
                                      AiPlanGenerationStatus.completed
                                  ? '查看 AI 方案'
                                  : 'AI 智能生成',
                        ),
                      ),
                      if (_aiRemaining != null &&
                          !_aiPlanController.isGenerating)
                        Text('$_aiRemaining 次',
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'local',
                  child: Row(children: [
                    Icon(Icons.event_repeat_outlined),
                    SizedBox(width: 12),
                    Text('本地生成 7 天计划'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'manual',
                  child: Row(children: [
                    Icon(Icons.edit_calendar_outlined),
                    SizedBox(width: 12),
                    Text('手动添加今天计划'),
                  ]),
                ),
              ],
            ),
          ),
          const _PlanWeekStrip(),
          const SizedBox(height: 16),
          _PlanTodaySummary(
              count: _plans
                  .where(
                      (plan) => DateUtils.isSameDay(plan.date, DateTime.now()))
                  .length),
          const SizedBox(height: 22),
          const Text('今天',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Column(
            children: [
              if (grouped.isEmpty)
                Column(
                  children: [
                    const _EmptyState(
                      icon: Icons.event_note_outlined,
                      text: '今天还没有安排，可以从一件小事开始。',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: () => _editPlan(date: DateTime.now()),
                        child: const Text('创建今天的计划')),
                  ],
                )
              else
                ...grouped.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DayPlanCard(
                      date: entry.key,
                      plans: entry.value,
                      filter: _filter,
                      onEdit: _editPlan,
                      onDelete: _deletePlan,
                      onAdd: () => _editPlan(
                        date: DateFormat('yyyy-MM-dd').parse(entry.key),
                      ),
                    ),
                  ),
                ),
            ],
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

  // ignore: unused_element
  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() => _filter = value);
  }

  Future<void> _editPlan({PlanRecordData? plan, DateTime? date}) async {
    final draft = await showDialog<_PlanDraft>(
      context: context,
      builder: (_) => _PlanEditDialog(plan: plan),
    );
    if (draft == null) return;
    try {
      if (plan == null) {
        await _repo.addPlan(
          date: date ?? DateTime.now(),
          type: draft.type,
          payload: draft.payload,
        );
      } else if (plan.id != null) {
        await _repo.updatePlan(plan.id!, payload: draft.payload);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(plan == null ? '计划项已添加' : '计划项已更新')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }

  Future<void> _deletePlan(PlanRecordData plan) async {
    if (plan.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除计划项'),
        content: const Text('删除后会同步到其他设备，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deletePlan(plan.id!);
  }
}

class _PlanWeekStrip extends StatelessWidget {
  const _PlanWeekStrip();
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: [
        for (var index = 0; index < 7; index++)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: index == now.weekday - 1
                    ? AppTheme.primaryBlue
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                Text(labels[index],
                    style: TextStyle(
                        fontSize: 12,
                        color: index == now.weekday - 1
                            ? Colors.white
                            : AppTheme.muted)),
                const SizedBox(height: 5),
                Text('${monday.add(Duration(days: index)).day}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: index == now.weekday - 1
                            ? Colors.white
                            : AppTheme.ink)),
              ]),
            ),
          ),
      ],
    );
  }
}

class _PlanTodaySummary extends StatelessWidget {
  const _PlanTodaySummary({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: AppTheme.deepBlue, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(count == 0 ? '今天还没有安排' : '今天有 $count 项安排',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const Text('从最容易完成的一项开始，按自己的节奏进行',
              style: TextStyle(color: Color(0xFFC7D7E5), fontSize: 13)),
          const SizedBox(height: 15),
          Container(height: 2, color: AppTheme.leafGreen),
        ]),
      );
}

class _PlanLoadingView extends StatelessWidget {
  const _PlanLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _PlanSkeletonBlock(height: 204),
        SizedBox(height: 16),
        _PlanSkeletonBlock(height: 132),
        SizedBox(height: 16),
        _PlanSkeletonBlock(height: 120),
      ],
    );
  }
}

class _SeniorPlanView extends StatelessWidget {
  const _SeniorPlanView({
    required this.todayPlans,
    required this.futurePlans,
    required this.doneTypes,
    required this.riskPlan,
    required this.onGoClock,
    required this.onAdjust,
    required this.onEdit,
    required this.onRefresh,
  });

  final List<PlanRecordData> todayPlans;
  final List<PlanRecordData> futurePlans;
  final Set<String> doneTypes;
  final PlanRecordData? riskPlan;
  final VoidCallback onGoClock;
  final Future<void> Function() onAdjust;
  final Future<void> Function({PlanRecordData? plan, DateTime? date}) onEdit;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = todayPlans.map((plan) {
      final clockType = plan.type == 'measurement' ? 'weight' : plan.type;
      return _SeniorPlanItem(
        plan: plan,
        completed: doneTypes.contains(clockType),
        hour: switch (plan.type) {
          'measurement' => 7,
          'meal' => 12,
          _ => 18,
        },
        minute: plan.type == 'exercise' ? 30 : 0,
      );
    }).toList()
      ..sort((a, b) {
        if (a.completed != b.completed) return a.completed ? 1 : -1;
        return (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
      });
    final current = items.where((item) => !item.completed).firstOrNull;
    final upcoming = items
        .where((item) => !item.completed && item != current)
        .take(2)
        .toList();
    final completed = items.where((item) => item.completed).toList();
    final bottomPad = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('senior-plan-scroll'),
        padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPad),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('今日计划',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              ),
              TextButton.icon(
                onPressed: onAdjust,
                icon: const Icon(Icons.tune),
                label: const Text('调整计划'),
              ),
            ],
          ),
          Text(
            DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(now),
            style: const TextStyle(fontSize: 17, color: AppTheme.muted),
          ),
          if (_isCriticalRiskPlan(riskPlan)) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.health_and_safety_outlined,
                      color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      riskPlan!.summary.isEmpty
                          ? '请根据健康风险提示合理执行今天的计划。'
                          : riskPlan!.summary,
                      style: const TextStyle(fontSize: 17, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (current == null)
            _SeniorPlanEmpty(onAdjust: onAdjust)
          else
            _SeniorCurrentPlan(
              item: current,
              onGoClock: onGoClock,
              onEdit: () => onEdit(plan: current.plan),
            ),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SeniorUpcomingPlans(
              items: upcoming,
              onGoClock: onGoClock,
              onEdit: onEdit,
            ),
          ],
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(
                  '今天已完成 ${completed.length} 项',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
                children: [
                  for (final item in completed)
                    ListTile(
                      leading:
                          const Icon(Icons.check_circle, color: Colors.green),
                      title: Text(_seniorPlanTitle(item.plan)),
                      trailing: TextButton(
                        onPressed: () => onEdit(plan: item.plan),
                        child: const Text('调整'),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (futurePlans.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SeniorFuturePlans(plans: futurePlans, onEdit: onEdit),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => onEdit(date: now),
            icon: const Icon(Icons.add),
            label: const Text('添加今天的计划'),
          ),
        ],
      ),
    );
  }
}

class _SeniorPlanItem {
  const _SeniorPlanItem({
    required this.plan,
    required this.completed,
    required this.hour,
    required this.minute,
  });

  final PlanRecordData plan;
  final bool completed;
  final int hour;
  final int minute;

  String get time =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class _SeniorCurrentPlan extends StatelessWidget {
  const _SeniorCurrentPlan({
    required this.item,
    required this.onGoClock,
    required this.onEdit,
  });

  final _SeniorPlanItem item;
  final VoidCallback onGoClock;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('当前计划',
              style: TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Text(item.time,
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(_seniorPlanIcon(item.plan.type),
                  size: 34, color: AppTheme.primaryBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_seniorPlanTitle(item.plan),
                    style: const TextStyle(
                        fontSize: 25, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          if (_seniorPlanDetail(item.plan).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _seniorPlanDetail(item.plan),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, color: AppTheme.muted),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onGoClock,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('去完成'),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('调整这一项'),
          ),
        ],
      ),
    );
  }
}

class _SeniorUpcomingPlans extends StatelessWidget {
  const _SeniorUpcomingPlans({
    required this.items,
    required this.onGoClock,
    required this.onEdit,
  });

  final List<_SeniorPlanItem> items;
  final VoidCallback onGoClock;
  final Future<void> Function({PlanRecordData? plan, DateTime? date}) onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('接下来',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 76,
                    child: Text(item.time,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  Icon(_seniorPlanIcon(item.plan.type),
                      color: AppTheme.primaryBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_seniorPlanTitle(item.plan),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () => onEdit(plan: item.plan),
                    child: const Text('调整'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SeniorFuturePlans extends StatelessWidget {
  const _SeniorFuturePlans({required this.plans, required this.onEdit});

  final List<PlanRecordData> plans;
  final Future<void> Function({PlanRecordData? plan, DateTime? date}) onEdit;

  Future<void> _showDayDetails(
    BuildContext context,
    DateTime date,
    List<PlanRecordData> dayPlans,
  ) async {
    final sorted = [...dayPlans]..sort((a, b) {
        const order = ['meal', 'exercise', 'measurement'];
        return order.indexOf(a.type).compareTo(order.indexOf(b.type));
      });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  DateFormat('M月d日 EEEE', 'zh_CN').format(date),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '当天共 ${sorted.length} 项计划',
                  style: const TextStyle(fontSize: 16, color: AppTheme.muted),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final plan = sorted[index];
                      final lines = _seniorPlanFullLines(plan);
                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppTheme.pageBg,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _seniorPlanIcon(plan.type),
                                  color: AppTheme.primaryBlue,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _seniorPlanTitle(plan),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (lines.isEmpty)
                              const Text(
                                '暂无详细说明',
                                style: TextStyle(color: AppTheme.muted),
                              )
                            else
                              for (final line in lines)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    line,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  onEdit(plan: plan);
                                },
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('调整这一项'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dates = <DateTime, List<PlanRecordData>>{};
    for (final plan in plans) {
      final date = plan.date;
      final key = DateTime(date.year, date.month, date.day);
      dates.putIfAbsent(key, () => []).add(plan);
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text('查看未来 7 天',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        children: [
          for (final entry in dates.entries)
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(DateFormat('M月d日 EEEE', 'zh_CN').format(entry.key)),
              subtitle: Text('${entry.value.length} 项 · 点击查看'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showDayDetails(context, entry.key, entry.value),
            ),
        ],
      ),
    );
  }
}

List<String> _seniorPlanFullLines(PlanRecordData plan) {
  final lines = <String>[];
  void add(String value) {
    final text = value.trim();
    if (text.isNotEmpty && !lines.contains(text)) lines.add(text);
  }

  add(plan.summary);
  if (plan.type == 'meal') {
    for (final entry in const [
      ('早餐', 'breakfast'),
      ('午餐', 'lunch'),
      ('晚餐', 'dinner'),
      ('加餐', 'snack'),
    ]) {
      final values = _stringList(plan.payload[entry.$2]);
      if (values.isNotEmpty) add('${entry.$1}：${values.join('、')}');
    }
  }
  for (final item in _stringList(plan.payload['items'])) {
    add('· $item');
  }
  final duration = plan.payload['durationMinutes'] ?? plan.payload['duration'];
  if (duration != null && duration.toString().trim().isNotEmpty) {
    final text = duration.toString().trim();
    add('建议时长：$text${RegExp(r'\d$').hasMatch(text) ? ' 分钟' : ''}');
  }
  return lines;
}

class _SeniorPlanEmpty extends StatelessWidget {
  const _SeniorPlanEmpty({required this.onAdjust});

  final Future<void> Function() onAdjust;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.event_available_outlined,
              size: 42, color: AppTheme.primaryBlue),
          const SizedBox(height: 10),
          const Text('今天还没有计划',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          FilledButton(onPressed: onAdjust, child: const Text('创建计划')),
        ],
      ),
    );
  }
}

String _seniorPlanTitle(PlanRecordData plan) => switch (plan.type) {
      'meal' => '饮食安排',
      'exercise' => '运动安排',
      'measurement' => '健康测量',
      _ => plan.label,
    };

IconData _seniorPlanIcon(String type) => switch (type) {
      'meal' => Icons.restaurant_outlined,
      'exercise' => Icons.directions_walk_outlined,
      'measurement' => Icons.monitor_heart_outlined,
      _ => Icons.event_note_outlined,
    };

String _seniorPlanDetail(PlanRecordData plan) {
  if (plan.summary.trim().isNotEmpty) return plan.summary.trim();
  final items = _stringList(plan.payload['items']);
  if (items.isNotEmpty) return items.take(2).join('；');
  for (final key in const ['breakfast', 'lunch', 'dinner']) {
    final values = _stringList(plan.payload[key]);
    if (values.isNotEmpty) return values.take(2).join('、');
  }
  return '';
}

class _PlanDraft {
  const _PlanDraft({required this.type, required this.payload});

  final String type;
  final Map<String, dynamic> payload;
}

class _PlanEditDialog extends StatefulWidget {
  const _PlanEditDialog({this.plan});

  final PlanRecordData? plan;

  @override
  State<_PlanEditDialog> createState() => _PlanEditDialogState();
}

class _PlanEditDialogState extends State<_PlanEditDialog> {
  late String _type;
  late final TextEditingController _summary;
  late final Map<String, TextEditingController> _fields;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _type = plan?.type ?? 'meal';
    final payload = plan?.payload ?? const <String, dynamic>{};
    _summary =
        TextEditingController(text: payload['summary']?.toString() ?? '');
    _fields = {
      for (final key in const [
        'breakfast',
        'lunch',
        'dinner',
        'snack',
        'exerciseType',
        'duration',
        'intensity',
        'description',
        'items',
      ])
        key: TextEditingController(
          text: _initialFieldText(key, payload),
        ),
    };
  }

  @override
  void dispose() {
    _summary.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.plan != null;
    return AlertDialog(
      title: Text(editing ? '编辑计划项' : '添加计划项'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: '类型'),
                items: const [
                  DropdownMenuItem(value: 'meal', child: Text('饮食')),
                  DropdownMenuItem(value: 'exercise', child: Text('运动')),
                  DropdownMenuItem(value: 'measurement', child: Text('测量')),
                ],
                onChanged: editing
                    ? null
                    : (value) => setState(() => _type = value ?? 'meal'),
              ),
              TextField(
                controller: _summary,
                decoration: const InputDecoration(labelText: '概括'),
                maxLength: 80,
              ),
              if (_type == 'meal') ...[
                for (final field in const [
                  ('breakfast', '早餐'),
                  ('lunch', '午餐'),
                  ('dinner', '晚餐'),
                  ('snack', '加餐'),
                ])
                  TextField(
                    controller: _fields[field.$1],
                    decoration: InputDecoration(labelText: '${field.$2}（每行一项）'),
                    maxLines: 2,
                  ),
              ] else if (_type == 'exercise') ...[
                TextField(
                  controller: _fields['exerciseType'],
                  decoration: const InputDecoration(labelText: '运动类型'),
                ),
                TextField(
                  controller: _fields['duration'],
                  decoration: const InputDecoration(labelText: '时长（分钟）'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: _fields['intensity'],
                  decoration: const InputDecoration(labelText: '强度'),
                ),
                TextField(
                  controller: _fields['description'],
                  decoration: const InputDecoration(labelText: '运动说明'),
                  maxLines: 3,
                ),
              ] else
                TextField(
                  controller: _fields['items'],
                  decoration: const InputDecoration(labelText: '测量项目（每行一项）'),
                  maxLines: 5,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _save() {
    final summary = _summary.text.trim();
    if (summary.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写计划概括')));
      return;
    }
    final payload = <String, dynamic>{'summary': summary};
    if (_type == 'meal') {
      for (final key in const ['breakfast', 'lunch', 'dinner', 'snack']) {
        payload[key] = _lines(_fields[key]!.text);
      }
    } else if (_type == 'exercise') {
      final type = _fields['exerciseType']!.text.trim();
      final duration = int.tryParse(_fields['duration']!.text.trim());
      final intensity = _fields['intensity']!.text.trim();
      final description = _fields['description']!.text.trim();
      if (type.isNotEmpty) payload['type'] = type;
      if (duration != null && duration > 0) {
        payload['duration'] = duration;
        payload['durationMinutes'] = duration;
      }
      if (intensity.isNotEmpty) payload['intensity'] = intensity;
      if (description.isNotEmpty) {
        payload['desc'] = description;
        payload['items'] = [description];
      }
    } else {
      payload['items'] = _lines(_fields['items']!.text);
    }
    Navigator.pop(context, _PlanDraft(type: _type, payload: payload));
  }

  static String _initialFieldText(String key, Map<String, dynamic> payload) {
    if (key == 'exerciseType') return payload['type']?.toString() ?? '';
    if (key == 'duration') {
      return (payload['durationMinutes'] ?? payload['duration'] ?? '')
          .toString();
    }
    if (key == 'intensity') return payload['intensity']?.toString() ?? '';
    if (key == 'description') {
      return (payload['desc'] ??
              (payload['items'] is List && (payload['items'] as List).isNotEmpty
                  ? (payload['items'] as List).first
                  : ''))
          .toString();
    }
    final raw = payload[key] ?? (key == 'items' ? payload['items'] : null);
    return raw is List ? raw.join('\n') : raw?.toString() ?? '';
  }

  static List<String> _lines(String value) => value
      .split(RegExp(r'[\r\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

class _PlanSkeletonBlock extends StatelessWidget {
  const _PlanSkeletonBlock({required this.height});

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

// ignore: unused_element
class _PlanHero extends StatelessWidget {
  const _PlanHero({
    required this.profile,
    required this.riskPlan,
    required this.targetKcal,
    required this.onGenerate,
    required this.onAiGenerate,
    required this.aiGenerating,
    required this.aiResultReady,
  });

  final UserProfileData? profile;
  final PlanRecordData? riskPlan;
  final int targetKcal;
  final VoidCallback onGenerate;
  final VoidCallback? onAiGenerate;
  final bool aiGenerating;
  final bool aiResultReady;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isAiPlan = _isAiPlanProvider(riskPlan?.aiProvider ?? '');
    final sourceColor = isAiPlan ? primary : AppTheme.cardBorder;
    final hasCompleteProfile = profile?.isComplete == true;
    final isCritical = _isCriticalRiskPlan(riskPlan);
    final canGenerate = hasCompleteProfile && !isCritical;
    final bmi = profile?.bmi ?? 0;
    final goalNote = riskPlan?.payload['goalNote'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAiPlan
              ? [
                  primary.withValues(alpha: 0.15),
                  primary.withValues(alpha: 0.06),
                  Colors.white,
                ]
              : const [Colors.white, AppTheme.pageBg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAiPlan
              ? sourceColor.withValues(alpha: 0.28)
              : AppTheme.cardBorder,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('7 天健康规划',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  if (riskPlan != null)
                    _PlanSourceBadge(
                      isAi: isAiPlan,
                      provider: riskPlan!.aiProvider,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isCritical
                    ? '检测到紧急健康风险，请立即就医，暂不提供健康或运动计划。'
                    : !hasCompleteProfile
                        ? '先完善档案，系统会基于 BMI、指标和目标生成个性化建议。'
                        : (goalNote.isNotEmpty
                            ? goalNote
                            : targetKcal > 0
                                ? '基于档案生成，每日约 $targetKcal kcal，低盐低脂高纤维。'
                                : '档案已完善，点击生成你的 7 天健康规划。'),
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
                      value: isCritical || targetKcal == 0
                          ? '--'
                          : '$targetKcal kcal'),
                  _InfoPill(
                      label: '状态',
                      value: isCritical
                          ? '需立即就医'
                          : hasCompleteProfile
                              ? profile!.bmiLevel
                              : '待完善'),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: canGenerate ? onGenerate : null,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                    label: const Text('本地生成'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          AppTheme.deepBlue.withValues(alpha: 0.15),
                      foregroundColor: AppTheme.deepBlue,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed:
                        !canGenerate || aiGenerating ? null : onAiGenerate,
                    icon: aiGenerating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(
                            aiResultReady
                                ? Icons.visibility_outlined
                                : Icons.psychology_outlined,
                            size: 16,
                          ),
                    label: Text(
                      aiGenerating
                          ? 'AI 生成中…'
                          : aiResultReady
                              ? '查看 AI 方案'
                              : 'AI 智能生成',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isCritical ? '紧急提示' : '生成规则',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (isCritical)
                  const Text('请停止运动并立即就医；如有明显不适，请呼叫急救。',
                      style: TextStyle(color: AppTheme.muted, height: 1.5))
                else ...[
                  const Text('· 风险评估 → 确定热量 → 饮食原则',
                      style: TextStyle(color: AppTheme.muted, height: 1.5)),
                  const Text('· 运动强度：有氧 + 力量 + 恢复轮替',
                      style: TextStyle(color: AppTheme.muted, height: 1.5)),
                  const Text('· 7 天饮食 / 运动 / 测量计划全覆盖',
                      style: TextStyle(color: AppTheme.muted, height: 1.5)),
                ],
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

// ignore: unused_element
class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.plan});

  final PlanRecordData plan;

  @override
  Widget build(BuildContext context) {
    final risks = _stringList(plan.payload['risks']);
    final isCritical = _isCriticalRiskPlan(plan);
    final summary = isCritical
        ? '检测到紧急健康风险，请立即就医，暂不提供健康或运动计划。'
        : plan.payload['summary']?.toString() ?? '';
    final dietNote =
        isCritical ? '' : plan.payload['dietNote']?.toString() ?? '';
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
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
  });

  final String date;
  final List<PlanRecordData> plans;
  final String filter;
  final Future<void> Function({PlanRecordData? plan, DateTime? date}) onEdit;
  final Future<void> Function(PlanRecordData plan) onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final displayDate =
        DateFormat('MM月dd日').format(DateFormat('yyyy-MM-dd').parse(date));
    final meals = plans.where((item) => item.type == 'meal').toList();
    final exercises = plans.where((item) => item.type == 'exercise').toList();
    final measurements =
        plans.where((item) => item.type == 'measurement').toList();
    final aiPlans =
        plans.where((item) => _isAiPlanProvider(item.aiProvider)).toList();
    final isAiPlan = aiPlans.isNotEmpty;
    final provider = isAiPlan ? aiPlans.first.aiProvider : 'local';
    final sourceColor = isAiPlan ? AppTheme.aiPurple : AppTheme.cardBorder;

    final showMeal = filter == 'all' || filter == 'meal';
    final showExercise = filter == 'all' || filter == 'exercise';
    final showMeasure = filter == 'all' || filter == 'measurement';

    final visibleCount = (showMeal ? meals.length : 0) +
        (showExercise ? exercises.length : 0) +
        (showMeasure ? measurements.length : 0);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAiPlan
              ? [
                  sourceColor.withValues(alpha: 0.12),
                  sourceColor.withValues(alpha: 0.04),
                  Colors.white,
                ]
              : const [Colors.white, AppTheme.pageBg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isAiPlan
              ? sourceColor.withValues(alpha: 0.28)
              : AppTheme.cardBorder,
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        title: Row(
          children: [
            Expanded(
              child: Text(displayDate,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            _PlanSourceBadge(isAi: isAiPlan, provider: provider),
          ],
        ),
        subtitle: Text('$visibleCount 条计划',
            style: const TextStyle(color: AppTheme.muted)),
        children: [
          if (showMeal)
            _MealDetailSection(
              items: meals,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          if (showExercise)
            _PlanSection(
              title: '运动计划',
              icon: Icons.directions_run_outlined,
              items: exercises,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          if (showMeasure)
            _MeasurementSection(
              items: measurements,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加计划项'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanSourceBadge extends StatelessWidget {
  const _PlanSourceBadge({required this.isAi, required this.provider});

  final bool isAi;
  final String provider;

  @override
  Widget build(BuildContext context) {
    final color = isAi ? AppTheme.aiPurple : AppTheme.muted;
    final label = isAi ? 'AI · ${_planProviderLabel(provider)}' : '本地规则';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isAi ? Icons.auto_awesome : Icons.tune, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
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
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final IconData icon;
  final List<PlanRecordData> items;
  final Future<void> Function({PlanRecordData? plan, DateTime? date}) onEdit;
  final Future<void> Function(PlanRecordData plan) onDelete;

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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.summary,
                      style:
                          const TextStyle(color: AppTheme.muted, height: 1.5),
                    ),
                  ),
                  IconButton(
                    tooltip: '编辑计划项',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => onEdit(plan: item),
                  ),
                  IconButton(
                    tooltip: '删除计划项',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => onDelete(item),
                  ),
                ],
              ),
              for (final detail in _stringList(item.payload['items']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('· $detail',
                      style:
                          const TextStyle(color: AppTheme.muted, height: 1.5)),
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
  const _MealDetailSection({
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final List<PlanRecordData> items;
  final Future<void> Function({PlanRecordData? plan, DateTime? date}) onEdit;
  final Future<void> Function(PlanRecordData plan) onDelete;

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
              Row(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  IconButton(
                    tooltip: '编辑计划项',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => onEdit(plan: item),
                  ),
                  IconButton(
                    tooltip: '删除计划项',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => onDelete(item),
                  ),
                ],
              ),
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
    if (raw is List) return _stringList(raw);
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
  const _MeasurementSection({
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final List<PlanRecordData> items;
  final Future<void> Function({PlanRecordData? plan, DateTime? date}) onEdit;
  final Future<void> Function(PlanRecordData plan) onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final allItems = <String>[];
    for (final plan in items) {
      final list = plan.payload['items'];
      if (list is List) allItems.addAll(_stringList(list));
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
              children: [
                const Icon(Icons.monitor_heart_outlined,
                    size: 18, color: AppTheme.deepBlue),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('每日测量',
                        style: TextStyle(fontWeight: FontWeight.w700))),
                for (final item in items) ...[
                  IconButton(
                    tooltip: '编辑计划项',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => onEdit(plan: item),
                  ),
                  IconButton(
                    tooltip: '删除计划项',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => onDelete(item),
                  ),
                ],
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

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .where((item) => item != null)
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

bool _isCriticalRiskPlan(PlanRecordData? plan) {
  if (plan?.payload['isCritical'] == true) return true;
  final risks = _stringList(plan?.payload['risks']);
  return risks.any(
    (risk) => risk.contains('高血压危象') || risk.contains('血氧饱和度危险偏低'),
  );
}

// ignore: unused_element
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.deepBlue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.deepBlue,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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

// ignore: unused_element
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

class _AiDisclaimerCard extends StatelessWidget {
  const _AiDisclaimerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.18)),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 14, color: AppTheme.primaryBlue),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            _aiDoctorDisclaimer,
            style: TextStyle(fontSize: 12, color: AppTheme.muted, height: 1.4),
          ),
        ),
      ]),
    );
  }
}

// ── AI 方案每日卡片 ───────────────────────────────────────────

class _AiDayCard extends StatefulWidget {
  const _AiDayCard({required this.day});
  final Map<String, dynamic> day;

  @override
  State<_AiDayCard> createState() => _AiDayCardState();
}

class _AiDayCardState extends State<_AiDayCard> {
  static const _collapsedReminderCount = 3;
  bool _remindersExpanded = false;

  @override
  Widget build(BuildContext context) {
    final weekDay = widget.day['weekDay'] as String? ?? '';
    final diet = _asMap(widget.day['diet']);
    final exercise = _asMap(widget.day['exercise']);
    final reminders =
        (widget.day['reminders'] as List?)?.map((item) => '$item').toList() ??
            [];
    final visibleReminders = _remindersExpanded
        ? reminders
        : reminders.take(_collapsedReminderCount).toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFFDFEFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.deepBlue.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue,
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
                Icons.restaurant_outlined, '饮食', AppTheme.primaryBlue),
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
            for (final r in visibleReminders)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(children: [
                  const Icon(Icons.circle, size: 5, color: AppTheme.muted),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(r, style: const TextStyle(fontSize: 13))),
                ]),
              ),
            if (reminders.length > _collapsedReminderCount)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _remindersExpanded = !_remindersExpanded),
                  icon: Icon(_remindersExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down),
                  label: Text(_remindersExpanded
                      ? '收起提醒'
                      : '展开全部 ${reminders.length} 条'),
                ),
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

class _InvalidAiPlanCard extends StatelessWidget {
  const _InvalidAiPlanCard({required this.message});

  final String message;

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
          const Row(children: [
            Icon(Icons.error_outline, size: 18, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              '方案格式异常',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: AppTheme.muted,
              height: 1.55,
              fontSize: 13,
            ),
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
