import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/data/ai_action_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/ai_api.dart';
import '../../core/membership/paywall.dart';
import '../../core/membership/membership_service.dart';
import '../../core/notification/reminder_consent.dart';
import '../../core/notification/reminder_scheduler.dart';
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
  final _membership = sl<MembershipService>();
  final _reminderScheduler = sl<ReminderScheduler>();

  bool _loading = true;
  bool _generating = false;
  bool _vipActive = false;
  String? _error;
  int _recordedDays = 0;
  Map<String, dynamic> _stats = const {};
  List<WeeklyHealthReportData> _reports = const [];
  List<Map<String, Object?>> _actionLogs = const [];

  DateTime get _endDate => DateUtils.dateOnly(DateTime.now());
  DateTime get _startDate =>
      _endDate.subtract(Duration(days: _vipActive ? 29 : 6));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      _vipActive = (await _membership.getStatus(forceRefresh: true)).isActive;
      final results = await Future.wait<Object>([
        _repo.loadIndicatorsSince(_startDate),
        _repo.loadMealsBetween(
          _startDate,
          _endDate.add(const Duration(days: 1)),
        ),
        _repo.loadClockRecords(limit: 500),
        _repo.loadWeeklyHealthReports(),
        AiActionRepository.instance.recent(limit: 10),
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
      final todayKey = DateFormat('yyyy-MM-dd').format(_endDate);
      final currentStreak = _currentStreak(days, _endDate);
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
        'currentStreak': currentStreak,
        'todayMealCount': meals
            .where((item) =>
                DateFormat('yyyy-MM-dd').format(item.eatenTime) == todayKey)
            .length,
        'todayCheckIns': clocks
            .where((item) =>
                item.status == 'done' &&
                DateFormat('yyyy-MM-dd').format(item.clockTime) == todayKey)
            .length,
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
        _recordedDays = days.length.clamp(0, _vipActive ? 30 : 7);
        _stats = stats;
        _reports = results[3] as List<WeeklyHealthReportData>;
        _actionLogs = results[4] as List<Map<String, Object?>>;
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
    if (!await confirmAiCreditUseIfNeeded(context, 'weekly_report')) return;
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
      if (error is DioException && isAiCreditError(error)) {
        await showAiCreditRequiredDialog(context);
      }
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
              boxShadow: [
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
                  '${DateFormat('M月d日').format(_startDate)}—${DateFormat('M月d日').format(_endDate)} · ${_vipActive ? 'VIP 深度分析' : '基础分析'}',
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
                              ? '生成${_vipActive ? '最近30天' : '最近7天'}周报'
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
          _DailySummary(stats: _stats, onCreateReminder: _createRecordReminder),
          _ActionLogSection(logs: _actionLogs, onUndo: _undoAction),
        ],
      ),
    );
  }

  Future<void> _undoAction(int id) async {
    final row = _actionLogs.where((item) => item['id'] == id).firstOrNull;
    final targetId = int.tryParse('${row?['target_id']}');
    if (row?['target_table'] == 'reminder' && targetId != null) {
      await _repo.deleteReminder(targetId);
      await _reminderScheduler.syncAll();
    }
    final ok = await AiActionRepository.instance.undo(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(ok ? '操作已撤销' : '操作已超过30分钟，无法撤销')));
    if (ok) {
      setState(() => _actionLogs = _actionLogs
          .map((row) => row['id'] == id ? {...row, 'status': 'undone'} : row)
          .toList());
    }
  }

  Future<void> _createRecordReminder(String type) async {
    if (await confirmReminderUse(context, _reminderScheduler) !=
        ReminderConsentResult.allowed) {
      return;
    }
    if (!mounted) return;
    final now = DateTime.now();
    final hour = type == 'meal' ? 19 : 20;
    final date = now.hour < hour ? now : now.add(const Duration(days: 1));
    final reminder = await _repo.addReminder(
      type: type,
      time: TimeOfDayValue(hour: hour, minute: 0),
      date: date,
      scheduleMode: 'once',
      weekdays: const [],
      note: type == 'meal' ? '今天还没有饮食记录，记得补充' : '今天还没有完成打卡，记得记录',
      payloadExtras: const {'source': 'record-summary'},
    );
    await _reminderScheduler.syncReminder(reminder);
    await AiActionRepository.instance.recordConfirmed(
      type: 'reminder',
      title: type == 'meal' ? '饮食记录提醒' : '健康打卡提醒',
      detail: '已创建一次性提醒',
      targetTable: 'reminder',
      targetId: reminder.id,
    );
    await _load();
  }

  int _currentStreak(Set<String> days, DateTime today) {
    var cursor = today;
    if (!days.contains(DateFormat('yyyy-MM-dd').format(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (days.contains(DateFormat('yyyy-MM-dd').format(cursor))) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }
}

class _DailySummary extends StatelessWidget {
  const _DailySummary({required this.stats, required this.onCreateReminder});
  final Map<String, dynamic> stats;
  final Future<void> Function(String type) onCreateReminder;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '今日摘要：已记录 ${stats['todayMealCount'] ?? 0} 条饮食、完成 ${stats['todayCheckIns'] ?? 0} 次打卡；当前连续记录 ${stats['currentStreak'] ?? 0} 天。',
              style: TextStyle(color: AppTheme.muted, height: 1.5)),
          if ((stats['todayMealCount'] as int? ?? 0) == 0)
            TextButton.icon(
                onPressed: () => onCreateReminder('meal'),
                icon: const Icon(Icons.notifications_none),
                label: const Text('提醒我记录饮食')),
          if ((stats['todayCheckIns'] as int? ?? 0) == 0)
            TextButton.icon(
                onPressed: () => onCreateReminder('exercise'),
                icon: const Icon(Icons.notifications_none),
                label: const Text('提醒我完成打卡')),
        ]),
      );
}

class _ActionLogSection extends StatelessWidget {
  const _ActionLogSection({required this.logs, required this.onUndo});
  final List<Map<String, Object?>> logs;
  final Future<void> Function(int id) onUndo;
  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      const Text('AI 操作记录',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      for (final row in logs)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(row['title']?.toString() ?? ''),
          subtitle: Text(row['status'] == 'undone'
              ? '已撤销'
              : (row['detail']?.toString() ?? '')),
          trailing: _canUndo(row)
              ? TextButton(
                  onPressed: () => onUndo(int.tryParse('${row['id']}') ?? 0),
                  child: const Text('撤销'))
              : null,
        ),
    ]);
  }

  bool _canUndo(Map<String, Object?> row) {
    if (row['status'] == 'undone' || row['target_id'] == null) return false;
    final createdAt = int.tryParse('${row['created_at']}') ?? 0;
    return DateTime.now().millisecondsSinceEpoch - createdAt <=
        const Duration(minutes: 30).inMilliseconds;
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
        boxShadow: [
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
            style: TextStyle(color: AppTheme.muted, height: 1.55),
          ),
          if (quality['message'] != null) ...[
            const SizedBox(height: 12),
            Text(
              '数据说明：${quality['message']}',
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
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
                leading: Icon(
                  Icons.check_circle_outline,
                  color: AppTheme.primaryBlue,
                ),
                title: Text(action['title']?.toString() ?? ''),
                subtitle: Text(action['detail']?.toString() ?? ''),
                trailing: IconButton(
                  tooltip: '去执行',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => _openAction(context, action),
                ),
              ),
          ],
          const SizedBox(height: 10),
          const AiContentNotice(feature: 'AI健康周报'),
        ],
      ),
    );
  }

  Future<void> _openAction(
      BuildContext context, Map<String, dynamic> action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认执行这条建议？'),
        content: Text('${action['title'] ?? ''}\n\n${action['detail'] ?? ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认并前往'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await AiActionRepository.instance.recordConfirmed(
      type: action['planType']?.toString() ?? 'unknown',
      title: action['title']?.toString() ?? '',
      detail: action['detail']?.toString() ?? '',
    );
    if (!context.mounted) return;
    switch (action['planType']?.toString()) {
      case 'meal':
        context.go('/meals');
        break;
      case 'exercise':
      case 'measurement':
        context.go('/plan');
        break;
      default:
        context.go('/clock');
    }
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
                    style: TextStyle(height: 1.5, color: AppTheme.muted)),
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
        child: Column(
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
