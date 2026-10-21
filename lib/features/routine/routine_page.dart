import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/auth/user_session.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../core/notification/reminder_consent.dart';
import '../../core/notification/reminder_scheduler.dart';
import 'routine_service.dart';
import 'routine_poster.dart';
import 'routine_chart.dart';
import 'routine_summary.dart';
import 'routine_goal_dialog.dart';
import 'routine_reminders.dart';
import '../../core/data/health_repository.dart';
import '../../core/network/api_response.dart';

class RoutinePage extends StatefulWidget {
  const RoutinePage({super.key, this.initialAction});
  final String? initialAction;
  @override
  State<RoutinePage> createState() => _RoutinePageState();
}

class _RoutinePageState extends State<RoutinePage> {
  final service = RoutineService(sl<ApiClient>());
  Map<String, dynamic>? data;
  List<Map> history = [];
  String? nextBefore;
  bool hasMore = false;
  bool busy = false;
  String? error;
  int days = 7;
  int loadVersion = 0;
  bool initialActionHandled = false;
  final account = UserSession.instance.userId;
  bool get active => mounted && account == UserSession.instance.userId;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final version = ++loadVersion;
    try {
      final result = await service.load(days: days);
      final start = DateTime.parse('${result['from']}T00:00:00+08:00');
      final legacy = await sl<HealthRepository>().loadIndicatorsSince(start);
      result['sessions'] =
          mergeRoutineSleep(List<Map>.from(result['sessions']), legacy)
              .where((row) =>
                  (row['date'] as String).compareTo(result['from']) >= 0 &&
                  (row['date'] as String).compareTo(result['to']) <= 0)
              .toList();
      final records = await service.history();
      if (!mounted || !active || version != loadVersion) return;
      setState(() {
        data = result;
        history = List<Map>.from(records['events']);
        nextBefore = records['nextBefore'];
        hasMore = records['hasMore'] == true;
        error = null;
      });
      if (!initialActionHandled) {
        initialActionHandled = true;
        final type = widget.initialAction;
        if (type == 'wake' || type == 'bed') {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!active) return;
            final today = routineDate(DateTime.now());
            final recorded = List<Map>.from(result['events']).where((event) =>
                event['eventType'] == type &&
                routineDate(DateTime.parse(event['occurredAt'])) == today);
            if (recorded.isNotEmpty) {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RoutinePoster(event: recorded.first)));
              return;
            }
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(type == 'wake' ? '记录现在起床？' : '记录现在准备睡觉？'),
                content: const Text('按当前北京时间记录。睡前到起床的间隔仅为估算休息时长。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认记录')),
                ],
              ),
            );
            if (confirmed == true && active) await checkIn(type!);
          });
        }
      }
    } catch (e) {
      if (active && version == loadVersion) setState(() => error = message(e));
    }
  }

  String message(Object e) => e is DioException
      ? e.error is ApiResponseException
          ? (e.error as ApiResponseException).message
          : '网络暂时不可用，请重试'
      : '操作未完成，请重试';
  void notify(String text) {
    if (active) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      notify(message(e));
    } finally {
      if (active) setState(() => busy = false);
    }
  }

  Future<void> checkIn(String type, {DateTime? at}) => perform(() async {
        final event = await service.checkIn(type, at: at);
        if (!mounted || !active) return;
        notify('已保存${type == 'wake' ? '早安' : '晚安'}记录');
        await reload();
        if (!mounted || !active) return;
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => RoutinePoster(event: event)));
      });

  Future<DateTime?> chooseTime({DateTime? initial}) async {
    final now = beijingTime(DateTime.now());
    final date = await showDatePicker(
        context: context,
        initialDate: initial ?? now,
        firstDate: DateTime(now.year, now.month, now.day - 6),
        lastDate: DateTime(now.year, now.month, now.day));
    if (date == null || !mounted || !active) return null;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial ?? now));
    if (time == null) return null;
    return DateTime.utc(date.year, date.month, date.day, time.hour, time.minute)
        .subtract(const Duration(hours: 8));
  }

  Future<void> backfill() async {
    final type = await showDialog<String>(
        context: context,
        builder: (context) =>
            SimpleDialog(title: const Text('补录最近 7 天'), children: [
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, 'wake'),
                  child: const Text('早安 · 起床')),
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, 'bed'),
                  child: const Text('晚安 · 准备睡觉')),
            ]));
    if (type == null || !active) return;
    final at = await chooseTime();
    if (at != null) await checkIn(type, at: at);
  }

  Future<void> edit(Map event) async {
    final at = await chooseTime(
        initial: beijingTime(DateTime.parse(event['occurredAt'])));
    if (at == null || !mounted || !active) return;
    final hours = TextEditingController(
        text: event['selfReportedHours']?.toString() ?? '');
    String? quality = event['quality'];
    String? hoursError;
    bool accepted = true;
    if (event['eventType'] == 'wake') {
      accepted = await showDialog<bool>(
              context: context,
              builder: (context) => StatefulBuilder(
                    builder: (context, update) => AlertDialog(
                        title: const Text('确认实际睡眠'),
                        content:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(
                              controller: hours,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  errorText: hoursError,
                                  labelText: '自报睡眠时长（小时，可留空）')),
                          DropdownButtonFormField<String>(
                              initialValue: quality,
                              decoration:
                                  const InputDecoration(labelText: '醒来感受（可选）'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'good', child: Text('精神不错')),
                                DropdownMenuItem(
                                    value: 'normal', child: Text('一般')),
                                DropdownMenuItem(
                                    value: 'poor', child: Text('仍感疲惫'))
                              ],
                              onChanged: (value) =>
                                  update(() => quality = value)),
                        ]),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () {
                                final value = double.tryParse(hours.text);
                                if (hours.text.isNotEmpty &&
                                    (value == null ||
                                        !value.isFinite ||
                                        value < 0.1 ||
                                        value > 24)) {
                                  update(
                                      () => hoursError = '请输入 0.1—24 小时，或留空');
                                  return;
                                }
                                Navigator.pop(context, true);
                              },
                              child: const Text('保存'))
                        ]),
                  )) ??
          false;
    }
    final value = double.tryParse(hours.text);
    hours.dispose();
    if (accepted && active) {
      await perform(() async {
        await service.edit(event, at, value, quality);
        await reload();
      });
    }
  }

  Future<void> remove(Map event) async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('删除这条作息记录？'),
                content: const Text('删除后会重新计算休息时长，无法恢复原早起比较资格。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'))
                ]));
    if (accepted == true && active) {
      await perform(() async {
        await service.delete(event);
        await reload();
      });
    }
  }

  Future<void> settings() async {
    final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => RoutineGoalDialog(
            settings: Map<String, dynamic>.from(data!['settings'])));
    if (selected != null && active) {
      await perform(() async {
        final scheduler = sl<ReminderScheduler>();
        if (selected['wakeReminder'] == true ||
            selected['bedReminder'] == true) {
          if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
            notify('作息通知目前支持 Android App，请选择不提醒');
            return;
          }
          final consent = await confirmReminderUse(context, scheduler);
          if (!active) return;
          if (consent != ReminderConsentResult.allowed) {
            notify('未保存修改。开启通知权限后可设置 APP 提醒，也可选择不提醒或手机闹钟');
            return;
          }
        }
        await service.settings(selected);
        await reload();
        try {
          await scheduler.syncAll();
        } catch (_) {
          notify('目标已保存，本机提醒同步失败，请重试');
        }
        if (!active) return;
        if (selected['wakeReminderMode'] == 'alarm') {
          if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
            notify('目标已保存，请在 Android 手机时钟设置闹钟');
            return;
          }
          try {
            await routineSystemAlarm(selected).launch();
            notify('请在手机时钟确认闹钟；后续修改或关闭也请在手机时钟操作');
          } catch (_) {
            notify('目标已保存，无法打开手机时钟，请手动设置闹钟或重新选择 APP 通知');
          }
        } else {
          notify(selected['wakeReminder'] == true ||
                  selected['bedReminder'] == true
              ? '作息目标已保存，APP 通知可能受系统限制延迟送达'
              : '作息目标已保存；已有系统闹钟请在手机时钟中管理');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = List<Map>.from(data?['events'] ?? []);
    final today = routineDate(DateTime.now());
    final todayEvents = events
        .where((e) => routineDate(DateTime.parse(e['occurredAt'])) == today);
    final sessions = List<Map>.from(data?['sessions'] ?? []);
    return Scaffold(
        appBar: AppBar(title: const Text('早晚安 · 作息重启'), actions: [
          IconButton(
              tooltip: '作息目标',
              onPressed: busy || data == null ? null : settings,
              icon: const Icon(Icons.tune)),
        ]),
        body: RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text('从一个从容的早晨，\n到一段安心的休息。',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text('按北京时间记录 · 睡前打卡表示准备休息，不等于已经入睡'),
              const SizedBox(height: 20),
              if (error != null) ...[
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                TextButton(onPressed: reload, child: const Text('重新加载'))
              ],
              if (data == null && error == null)
                const Center(child: CircularProgressIndicator()),
              for (final type in ['wake', 'bed'])
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FilledButton.tonalIcon(
                        onPressed:
                            busy || data == null ? null : () => checkIn(type),
                        icon: Icon(type == 'wake'
                            ? Icons.wb_sunny_outlined
                            : Icons.bedtime_outlined),
                        label: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                                '${type == 'wake' ? '早安，我起床了' : '晚安，准备休息'}${todayEvents.any((e) => e['eventType'] == type) ? ' · 已记录，查看海报' : ''}')))),
              TextButton.icon(
                  onPressed: busy || data == null ? null : backfill,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('补录最近 7 天')),
              TextButton.icon(
                  onPressed: busy || data == null ? null : settings,
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('设置作息提醒')),
              const SizedBox(height: 20),
              SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 天')),
                    ButtonSegment(value: 30, label: Text('30 天'))
                  ],
                  selected: {
                    days
                  },
                  onSelectionChanged: busy
                      ? null
                      : (value) {
                          setState(() => days = value.first);
                          reload();
                        }),
              const SizedBox(height: 16),
              Text('休息趋势', style: Theme.of(context).textTheme.titleLarge),
              const Text('自报睡眠优先展示；估算仅为睡前到起床的间隔。'),
              if (data != null && sessions.isNotEmpty)
                RoutineChart(
                    rows: sessions,
                    days: days,
                    endDate: data!['to'],
                    target: data!['settings']['restTargetHours']),
              if (sessions.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('还没有起床记录。完成一次早晚安，开始了解自己的节奏。')),
              for (final row in sessions)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row['selfReportedHours'] != null ||
                                  row['estimatedHours'] != null
                              ? '${row['date']} · ${row['selfReportedHours'] != null ? '自报睡眠' : '估算休息'} ${((row['selfReportedHours'] ?? row['estimatedHours']) as num).toStringAsFixed(1)} 小时'
                              : '${row['date']} · ${row['status'] == 'missing_bed' ? '缺少晚安记录，暂无法估算休息时长' : '休息间隔待确认，可在记录中确认实际睡眠'}'),
                          if (row['sleepSource'] != null)
                            Text(row['sleepSource']),
                          if (row['selfReportedHours'] != null ||
                              row['estimatedHours'] != null)
                            LinearProgressIndicator(
                                value: (((row['selfReportedHours'] ??
                                            row['estimatedHours']) as num) /
                                        16)
                                    .clamp(0, 1),
                                minHeight: 10),
                        ])),
              const SizedBox(height: 24),
              Text('作息记录', style: Theme.of(context).textTheme.titleLarge),
              const Text('最近 7 天可修改；所有历史记录均可删除。补录和修改不参与早起比较。'),
              for (final event in history.reversed)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(event['eventType'] == 'wake'
                        ? Icons.wb_sunny_outlined
                        : Icons.bedtime_outlined),
                    title: Text(DateFormat('MM-dd HH:mm').format(
                        beijingTime(DateTime.parse(event['occurredAt'])))),
                    subtitle: Text(
                        '${event['eventType'] == 'wake' ? '起床' : '睡前'} · ${event['source'] == 'live' ? '实时打卡' : '补录 / 修改'}'),
                    onTap: busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => RoutinePoster(event: event))),
                    trailing: PopupMenuButton<String>(
                        enabled: !busy,
                        onSelected: (value) =>
                            value == 'delete' ? remove(event) : edit(event),
                        itemBuilder: (_) => [
                              if (routineDate(
                                          DateTime.parse(event['occurredAt']))
                                      .compareTo(routineDate(DateTime.now()
                                          .subtract(
                                              const Duration(days: 6)))) >=
                                  0)
                                const PopupMenuItem(
                                    value: 'edit', child: Text('修改 / 确认睡眠')),
                              const PopupMenuItem(
                                  value: 'delete', child: Text('删除')),
                            ])),
              if (hasMore)
                TextButton(
                    onPressed: busy
                        ? null
                        : () => perform(() async {
                              final result = await service.history(nextBefore);
                              if (active) {
                                setState(() {
                                  history = [
                                    ...List<Map>.from(result['events']),
                                    ...history
                                  ];
                                  nextBefore = result['nextBefore'];
                                  hasMore = result['hasMore'] == true;
                                });
                              }
                            }),
                    child: const Text('加载更早记录')),
              if (busy) const LinearProgressIndicator(),
            ])));
  }
}
