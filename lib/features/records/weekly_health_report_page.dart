import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/ai_api.dart';
import '../../core/privacy/ai_consent_gate.dart';
import '../../core/widgets/ai_content_notice.dart';

class WeeklyHealthReportPage extends StatefulWidget {
  const WeeklyHealthReportPage({super.key});

  @override
  State<WeeklyHealthReportPage> createState() => _WeeklyHealthReportPageState();
}

class _WeeklyHealthReportPageState extends State<WeeklyHealthReportPage> {
  final _repo = sl<HealthRepository>();
  final _api = sl<AiApi>();

  bool _loading = true;
  bool _generating = false;
  String? _error;
  int _recordedDays = 0;
  Map<String, dynamic> _stats = const {};
  List<WeeklyHealthReportData> _reports = const [];

  DateTime get _endDate => DateUtils.dateOnly(DateTime.now());
  DateTime get _startDate => _endDate.subtract(const Duration(days: 6));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait<Object>([
        _repo.loadIndicatorsSince(_startDate),
        _repo.loadMealsBetween(
          _startDate,
          _endDate.add(const Duration(days: 1)),
        ),
        _repo.loadClockRecords(limit: 500),
        _repo.loadWeeklyHealthReports(),
      ]);
      final indicators = results[0] as List<HealthIndicatorEntry>;
      final meals = results[1] as List<MealRecordData>;
      final clocks = (results[2] as List<ClockRecordData>)
          .where((item) => !item.clockTime.isBefore(_startDate))
          .toList();
      final days = <String>{
        for (final item in indicators)
          DateFormat('yyyy-MM-dd').format(item.measuredTime),
        for (final item in meals)
          DateFormat('yyyy-MM-dd').format(item.eatenTime),
        for (final item in clocks)
          DateFormat('yyyy-MM-dd').format(item.clockTime),
      };
      final calories = meals.fold<double>(
        0,
        (sum, item) => sum + item.totalCalories,
      );
      final protein = meals.fold<double>(
        0,
        (sum, item) => sum + item.proteinG,
      );
      final weights = indicators.where((item) => item.type == 'weight').toList()
        ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
      final sleepValues = indicators
          .where((item) => item.type == 'sleep')
          .map((item) => (item.payload['sleepHours'] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      final exerciseDays = clocks
          .where((item) => item.type == 'exercise' && item.status == 'done')
          .map((item) => DateFormat('yyyy-MM-dd').format(item.clockTime))
          .toSet()
          .length;
      final stats = <String, dynamic>{
        'recordedDays': days.length,
        'mealDays': meals
            .map((item) => DateFormat('yyyy-MM-dd').format(item.eatenTime))
            .toSet()
            .length,
        'mealCount': meals.length,
        'averageDailyCalories': days.isEmpty ? 0 : (calories / days.length),
        'averageDailyProteinG': days.isEmpty ? 0 : (protein / days.length),
        'exerciseDays': exerciseDays,
        'completedCheckIns':
            clocks.where((item) => item.status == 'done').length,
        'indicatorCount': indicators.length,
        if (weights.length >= 2)
          'weightChangeKg': (weights.last.numericTrendValue ?? 0) -
              (weights.first.numericTrendValue ?? 0),
        if (sleepValues.isNotEmpty)
          'averageSleepHours':
              sleepValues.reduce((a, b) => a + b) / sleepValues.length,
      };
      if (!mounted) return;
      setState(() {
        _recordedDays = days.length.clamp(0, 7);
        _stats = stats;
        _reports = results[3] as List<WeeklyHealthReportData>;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '暂时无法读取最近7天记录，请稍后重试。';
        _loading = false;
      });
    }
  }

  Future<void> _generate() async {
    if (_recordedDays < 3 || _generating) return;
    if (!await ensureAiConsent(context)) return;
    if (!mounted) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final result = await _api.generateWeeklyHealthReport({
        'provider': 'qwen',
        'startDate': DateFormat('yyyy-MM-dd').format(_startDate),
        'endDate': DateFormat('yyyy-MM-dd').format(_endDate),
        'recordedDays': _recordedDays,
        'stats': _stats,
      });
      await _repo.saveWeeklyHealthReport(
        startDate: _startDate,
        endDate: _endDate,
        structured: result.data,
        provider: result.provider,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyAiError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final colors = Theme.of(context).colorScheme;
    final latest = _reports.firstOrNull;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const PageStorageKey('weekly-health-report'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.accentGradient(context),
              borderRadius: BorderRadius.circular(20),
              boxShadow:  [
                BoxShadow(
                  color: AppTheme.softShadow,
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 健康周报',
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${DateFormat('M月d日').format(_startDate)}—${DateFormat('M月d日').format(_endDate)} · 已记录 $_recordedDays/7 天',
                  style: TextStyle(
                    color: colors.onPrimary.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed:
                      _recordedDays < 3 || _generating ? null : _generate,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.onPrimary,
                    foregroundColor: colors.primary,
                    disabledBackgroundColor:
                        colors.onPrimary.withValues(alpha: 0.52),
                    disabledForegroundColor:
                        colors.primary.withValues(alpha: 0.96),
                    side: BorderSide(
                      color: colors.onPrimary.withValues(alpha: 0.76),
                    ),
                  ),
                  icon: _generating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _recordedDays < 3
                              ? Icons.hourglass_bottom_outlined
                              : Icons.auto_awesome_outlined,
                        ),
                  label: Text(_generating
                      ? '正在生成'
                      : _recordedDays < 3
                          ? '还差 ${3 - _recordedDays} 天可生成'
                          : latest == null
                              ? '生成最近7天周报'
                              : '重新生成'),
                ),
                if (_recordedDays < 3) ...[
                  const SizedBox(height: 10),
                  Text(
                    '还需记录 ${3 - _recordedDays} 天，数据足够后才能生成有依据的周报。',
                    style: TextStyle(
                      color: colors.onPrimary.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _ReportMessage(message: _error!, onRetry: _generate),
          ],
          if (latest != null) ...[
            const SizedBox(height: 16),
            _WeeklyReportBody(report: latest),
          ] else ...[
            const SizedBox(height: 16),
            const _ReportEmpty(),
          ],
        ],
      ),
    );
  }
}

class _WeeklyReportBody extends StatelessWidget {
  const _WeeklyReportBody({required this.report});

  final WeeklyHealthReportData report;

  @override
  Widget build(BuildContext context) {
    final data = report.structured;
    final wins = _strings(data['wins']);
    final concerns = _strings(data['concerns']);
    final actions = _maps(data['actions']);
    final quality = _map(data['dataQuality']);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        boxShadow:  [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data['title']?.toString() ?? '最近7天健康周报',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            data['summary']?.toString() ?? '',
            style:  TextStyle(color: AppTheme.muted, height: 1.55),
          ),
          if (quality['message'] != null) ...[
            const SizedBox(height: 12),
            Text(
              '数据说明：${quality['message']}',
              style:  TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ],
          if (wins.isNotEmpty) _ReportSection(title: '做得不错', items: wins),
          if (concerns.isNotEmpty)
            _ReportSection(title: '值得关注', items: concerns),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              '下周三个行动',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final action in actions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:  Icon(
                  Icons.check_circle_outline,
                  color: AppTheme.primaryBlue,
                ),
                title: Text(action['title']?.toString() ?? ''),
                subtitle: Text(action['detail']?.toString() ?? ''),
              ),
          ],
          const SizedBox(height: 10),
          const AiContentNotice(feature: 'AI健康周报'),
        ],
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• $item',
                    style:  TextStyle(height: 1.5, color: AppTheme.muted)),
              ),
          ],
        ),
      );
}

class _ReportEmpty extends StatelessWidget {
  const _ReportEmpty();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child:  Column(
          children: [
            Icon(Icons.summarize_outlined,
                size: 42, color: AppTheme.primaryBlue),
            SizedBox(height: 10),
            Text('还没有健康周报',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('周报只使用你最近7天真实记录的数据。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted)),
          ],
        ),
      );
}

class _ReportMessage extends StatelessWidget {
  const _ReportMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
}

String _friendlyAiError(Object error) {
  if (error is FormatException) return error.message;
  if (error is DioException) {
    final body = error.response?.data;
    if (body is Map) {
      final message = '${body['msg'] ?? body['message'] ?? ''}'.trim();
      if (message.isNotEmpty) return message;
    }
    if (error.message?.isNotEmpty == true) return error.message!;
  }
  final text = error.toString();
  if (text.contains('42901')) return '今天的 AI 使用次数已用完，请明天再试。';
  if (text.contains('40301') || text.contains('401')) return '请先登录账号后再生成周报。';
  if (text.contains('50301')) return '当前 AI 模型暂时不可用，请稍后重试。';
  if (text.contains('50302')) return 'AI 返回的周报格式不完整，请重新生成。';
  return '周报生成失败，请检查网络后重试。';
}

Map<String, dynamic> _map(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry('$key', value))
    : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? raw) => raw is List
    ? raw.whereType<Map>().map(_map).toList(growable: false)
    : const [];

List<String> _strings(Object? raw) => raw is List
    ? raw.map((item) => '$item').where((item) => item.isNotEmpty).toList()
    : const [];
