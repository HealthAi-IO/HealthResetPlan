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
import '../../core/network/ai_api.dart';
import '../../core/network/telemetry_api.dart';
import '../../core/notification/reminder_consent.dart';
import '../../core/notification/reminder_scheduler.dart';
import '../../core/privacy/ai_consent_gate.dart';
import '../../core/widgets/ai_content_notice.dart';
import '../../core/widgets/health_ui.dart';

part 'plan_widgets.dart';

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
  int? _aiRemaining;
  int _handledAiEventId = 0;
  _PlanGoalDraft? _goalDraft;
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  DateTime _calendarMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _aiPlanController.addListener(_onAiPlanGenerationChanged);
    AppRouter.router.routeInformationProvider.addListener(_onRouteChanged);
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
    AppRouter.router.routeInformationProvider.removeListener(_onRouteChanged);
    super.dispose();
  }

  void _onRouteChanged() {
    if (AppRouter.router.routeInformationProvider.value.uri.path == '/plan') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onAiPlanGenerationChanged();
      });
    }
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_aiPlanController.usedLocalFallback) {
          _handleLocalFallback();
        } else {
          _presentAiResult();
        }
      });
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
    final plans = await _repo.loadPlans(limit: 1000);
    final clockRecords = await _repo.loadClockRecords(limit: 40);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      final riskList = plans.where((p) => p.type == 'risk').toList();
      _riskPlan = riskList.isEmpty ? null : riskList.first;
      final isCritical = _isCriticalRiskPlan(_riskPlan);
      _plans = isCritical
          ? const []
          : plans
              .where((p) => p.type == 'exercise' || p.type == 'measurement')
              .toList();
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
          duration: const Duration(seconds: 5),
          content: const Text('请先完善性别、出生年份、身高和体重，再生成运动计划'),
          action: SnackBarAction(
              label: '去完善', onPressed: () => context.push('/profile')),
        ),
      );
      return;
    }
    if (!await _confirmReplacePlans()) return;
    try {
      await _repo.generateWeeklyPlan(goal: _goalDraft?.code);
      sl<TelemetryApi>().record('plan_generated');
      if (!mounted) return;
      messenger
          .showSnackBar(const SnackBar(content: Text('已根据你的档案生成 7 天运动计划')));
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
    if (!_plans.any((plan) => plan.type == 'exercise')) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('替换未来运动计划吗？'),
            content: const Text('新的 7 天运动计划只会替换今天及未来的运动安排，每日测量和历史记录都会保留。'),
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

  Future<_PlanApplyMode?> _chooseApplyMode() async {
    if (!_plans.any((plan) => plan.type == 'exercise')) {
      return _PlanApplyMode.replace;
    }
    return showDialog<_PlanApplyMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('如何应用专属计划？'),
        content: const Text(
          '替换会更新今天及未来的运动安排；合并会保留现有计划，并加入新方案。历史记录不会受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('暂不应用'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, _PlanApplyMode.merge),
            child: const Text('合并计划'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _PlanApplyMode.replace),
            child: const Text('替换计划'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateWithAi() async {
    // 1. 登录校验：所有登录用户均可使用 AI 能力。
    if (!mounted) return;
    if (_profile == null ||
        !_profile!.isComplete ||
        _profile!.gender == 'unknown') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: const Text('请先完善性别、出生年份、身高和体重，再生成个性化 AI 运动计划'),
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
    final goalDraft = await showModalBottomSheet<_PlanGoalDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PlanGoalSheet(initialValue: _goalDraft),
    );
    if (goalDraft == null || !mounted) return;
    setState(() => _goalDraft = goalDraft);
    if (!mounted) return;
    if (!await ensureAiConsent(context)) return;
    if (!mounted) return;
    // 2. 弹出模型选择对话框
    final provider = await _showProviderPicker();
    if (provider == null || !mounted) return;
    setState(() => _selectedProvider = provider);
    _aiPlanController.start(
      profile: _profile!,
      provider: provider,
      goal: goalDraft.code,
      goalDetail: goalDraft.detail,
      targetDate: goalDraft.targetDate,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI 已开始生成运动计划，你可以继续使用其他功能')),
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_friendlyError(error ?? 'AI 生成失败')),
        backgroundColor: Colors.orange.shade700,
      ),
    );
    _aiPlanController.clear();
  }

  Future<void> _handleLocalFallback() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI 暂时不可用，已准备本地详细方案，请确认后应用'),
      ),
    );
    await _presentAiResult();
  }

  Future<String?> _showProviderPicker() {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.72,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Text('选择 AI 模型',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('方案质量因模型而异，可切换尝试',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 16),
            for (final p in [
              ('doubao', '🫘', '豆包 Seed 2.1 Pro', '响应更快，适合生成 7 天运动计划'),
              ('qwen', '🌟', '通义千问 3.7 Plus', '默认模型，支持运动计划生成'),
              ('glm', 'GLM', '智谱 GLM-5.2', '适合生成结构化动作安排'),
              ('deepseek', '🤖', 'DeepSeek V4 Pro', '推理能力强，便于细化动作和替代方案'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(p.$2, style: const TextStyle(fontSize: 24)),
                title: Text(p.$3,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(p.$4,
                    style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                trailing: _selectedProvider == p.$1
                    ? Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      )
                    : null,
                onTap: () => Navigator.pop(sheetContext, p.$1),
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
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                  Icon(
                    Icons.psychology_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('AI 运动计划',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: Text(_planProviderLabel(result.provider),
                        style: TextStyle(fontSize: 11, color: AppTheme.muted)),
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
                    const AiContentNotice(feature: 'AI运动计划'),
                    const SizedBox(height: 8),
                    Text(summary,
                        style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                    if (keyFocus.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(
                          Icons.flag_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '本周重点：$keyFocus',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                              final applyMode = await _chooseApplyMode();
                              if (applyMode == null) return;
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
                                  replaceExisting:
                                      applyMode == _PlanApplyMode.replace,
                                );
                                if (createReminders) {
                                  await _reminderScheduler.syncAll();
                                }
                                if (mounted) {
                                  _aiPlanController.clear();
                                  await _load(silent: true);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      duration: const Duration(seconds: 5),
                                      content: Text(
                                        createReminders
                                            ? '专属计划和提醒已应用'
                                            : '专属计划已应用，未开启提醒',
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
                      label: Text(!hasExecutablePlan ? '无法应用' : '应用运动计划'),
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

  String _friendlyError(Object e) {
    if (e is FormatException) return e.message;
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
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
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
                    : 'AI 智能生成 7 天运动计划'),
              ),
              if (_aiRemaining != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '今天还可使用 $_aiRemaining 次',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _generate();
                },
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('按本地规则生成 7 天运动计划'),
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

    final selectedKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final grouped = Map<String, List<PlanRecordData>>.fromEntries(
      _groupPlans().entries.where((entry) => entry.key == selectedKey),
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
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
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
                    _editPlan(date: _selectedDate);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'ai',
                  enabled: !_aiPlanController.isGenerating,
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
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
                            style:
                                TextStyle(color: AppTheme.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'local',
                  child: Row(children: [
                    Icon(Icons.event_repeat_outlined),
                    SizedBox(width: 12),
                    Text('本地生成 7 天运动计划'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'manual',
                  child: Row(children: [
                    Icon(Icons.edit_calendar_outlined),
                    SizedBox(width: 12),
                    Text('手动添加所选日期计划'),
                  ]),
                ),
              ],
            ),
          ),
          _PersonalGoalCard(
            goal: _goalDraft,
            generating: _aiPlanController.isGenerating,
            onCreate: _aiPlanController.isGenerating ? null : _generateWithAi,
          ),
          const SizedBox(height: 18),
          _PlanTodaySummary(
            count: _plans
                .where((plan) => DateUtils.isSameDay(plan.date, _selectedDate))
                .length,
            date: _selectedDate,
          ),
          const SizedBox(height: 22),
          Text(
              DateUtils.isSameDay(_selectedDate, DateTime.now())
                  ? '今天'
                  : DateFormat('M月d日 EEEE', 'zh_CN').format(_selectedDate),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Column(
            children: [
              if (grouped.isEmpty)
                Column(
                  children: [
                    _EmptyState(
                      icon: Icons.event_note_outlined,
                      text:
                          '${DateUtils.isSameDay(_selectedDate, DateTime.now()) ? '今天' : '这一天'}还没有安排，可以从一件小事开始。',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: () => _editPlan(date: _selectedDate),
                        child: const Text('创建所选日期的计划')),
                  ],
                )
              else
                ...grouped.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DayPlanCard(
                      date: entry.key,
                      plans: entry.value,
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
          const SizedBox(height: 24),
          Text(
            '选择其他日期',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          _PlanCalendar(
            month: _calendarMonth,
            selectedDate: _selectedDate,
            plans: _plans,
            onMonthChanged: (month) => setState(() {
              _calendarMonth = month;
              _selectedDate = DateTime(month.year, month.month, 1);
            }),
            onDateSelected: (date) => setState(() => _selectedDate = date),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Map<String, List<PlanRecordData>> _groupPlans() {
    final map = <String, List<PlanRecordData>>{};
    for (final plan in _plans) {
      final key = DateFormat('yyyy-MM-dd').format(plan.date);
      map.putIfAbsent(key, () => []).add(plan);
    }
    return map;
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
