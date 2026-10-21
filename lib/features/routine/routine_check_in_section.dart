import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import 'routine_service.dart';

class RoutineCheckInSection extends StatefulWidget {
  const RoutineCheckInSection({super.key});

  @override
  State<RoutineCheckInSection> createState() => _RoutineCheckInSectionState();
}

class _RoutineCheckInSectionState extends State<RoutineCheckInSection> {
  final service = RoutineService(sl<ApiClient>());
  late Future<Map<String, dynamic>> status = service.load();

  void refresh() => setState(() => status = service.load());

  Future<void> open([String? type]) async {
    await context.push(type == null ? '/routine' : '/routine?action=$type');
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('作息', style: theme.textTheme.titleMedium)),
              TextButton(onPressed: () => open(), child: const Text('作息趋势')),
            ]),
            const Text('起床与睡前，留一份休息记录'),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: status,
              builder: (context, snapshot) {
                final events = List<Map>.from(snapshot.data?['events'] ?? []);
                final today = routineDate(DateTime.now());
                final loading =
                    snapshot.connectionState != ConnectionState.done;
                final buttons = [
                  for (final type in ['wake', 'bed'])
                    OutlinedButton(
                      onPressed: loading || snapshot.hasError
                          ? null
                          : () => open(type),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 80),
                        padding: const EdgeInsets.all(12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(type == 'wake'
                            ? Icons.wb_sunny_outlined
                            : Icons.bedtime_outlined),
                        const SizedBox(height: 8),
                        Text(type == 'wake' ? '早安 · 起床' : '晚安 · 准备睡觉',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        Text(
                            loading
                                ? '加载中'
                                : snapshot.hasError
                                    ? '暂不可用'
                                    : events.any((event) =>
                                            event['eventType'] == type &&
                                            routineDate(DateTime.parse(
                                                    event['occurredAt'])) ==
                                                today)
                                        ? '今日已记录 · 查看海报'
                                        : '今日未记录',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center),
                      ]),
                    ),
                ];
                return Column(children: [
                  LayoutBuilder(builder: (context, constraints) {
                    if (MediaQuery.textScalerOf(context).scale(16) > 24) {
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buttons[0],
                            const SizedBox(height: 12),
                            buttons[1]
                          ]);
                    }
                    return IntrinsicHeight(child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: buttons[0]),
                          const SizedBox(width: 12),
                          Expanded(child: buttons[1])
                        ]));
                  }),
                  if (snapshot.hasError)
                    TextButton(
                        onPressed: refresh, child: const Text('作息状态加载失败，点击重试')),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}
