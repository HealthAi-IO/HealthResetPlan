part of 'plan_page.dart';

class _PlanCalendar extends StatelessWidget {
  const _PlanCalendar({
    required this.month,
    required this.selectedDate,
    required this.plans,
    required this.onMonthChanged,
    required this.onDateSelected,
  });

  final DateTime month;
  final DateTime selectedDate;
  final List<PlanRecordData> plans;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final leading = first.weekday - 1;
    final dayCount = DateUtils.getDaysInMonth(month.year, month.month);
    final counts = <int, int>{};
    for (final plan in plans) {
      final date = plan.date;
      if (date.year == month.year &&
          date.month == month.month &&
          plan.type != 'risk') {
        counts.update(date.day, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '上个月',
                onPressed: () => onMonthChanged(
                  DateTime(month.year, month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  DateFormat('yyyy年M月', 'zh_CN').format(month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '下个月',
                onPressed: () => onMonthChanged(
                  DateTime(month.year, month.month + 1),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leading + dayCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 46,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemBuilder: (context, index) {
              if (index < leading) return const SizedBox.shrink();
              final date = DateTime(
                month.year,
                month.month,
                index - leading + 1,
              );
              final selected = DateUtils.isSameDay(date, selectedDate);
              final isToday = DateUtils.isSameDay(date, DateTime.now());
              final count = counts[date.day] ?? 0;
              return Semantics(
                button: true,
                selected: selected,
                label: '${date.month}月${date.day}日，$count项计划',
                child: InkWell(
                  onTap: () => onDateSelected(date),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primary
                          : count > 0
                              ? colors.primaryContainer.withValues(alpha: 0.7)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: isToday && !selected
                          ? Border.all(color: colors.primary)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            color:
                                selected ? colors.onPrimary : colors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (count > 0)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(top: 3),
                            decoration: BoxDecoration(
                              color:
                                  selected ? colors.onPrimary : colors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PlanTodaySummary extends StatelessWidget {
  const _PlanTodaySummary({required this.count, required this.date});
  final int count;
  final DateTime date;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            gradient: AppTheme.accentGradient(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.softShadow,
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              count == 0
                  ? '${DateUtils.isSameDay(date, DateTime.now()) ? '今天' : DateFormat('M月d日').format(date)}还没有安排'
                  : '${DateUtils.isSameDay(date, DateTime.now()) ? '今天' : DateFormat('M月d日').format(date)}有 $count 项安排',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const Text('从最容易完成的一项开始，按自己的节奏进行',
              style: TextStyle(color: Color(0xFFFFF5EE), fontSize: 13)),
          const SizedBox(height: 15),
          Container(
            height: 2,
            color:
                Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.5),
          ),
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
                        TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
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
            style: TextStyle(fontSize: 17, color: AppTheme.muted),
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
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
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
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('当前计划',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Text(item.time,
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _seniorPlanIcon(item.plan.type),
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_seniorPlanTitle(item.plan),
                    style: const TextStyle(
                        fontSize: 25, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (_seniorPlanDetail(item.plan).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _seniorPlanDetail(item.plan),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, color: AppTheme.muted),
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('接下来',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
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
                  Icon(
                    _seniorPlanIcon(item.plan.type),
                    color: Theme.of(context).colorScheme.primary,
                  ),
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '当天共 ${sorted.length} 项计划',
                  style: TextStyle(fontSize: 16, color: AppTheme.muted),
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
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _seniorPlanIcon(plan.type),
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _seniorPlanTitle(plan),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (lines.isEmpty)
                              Text(
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 42,
            color: Theme.of(context).colorScheme.primary,
          ),
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
    _type = plan?.type ?? 'exercise';
    final payload = plan?.payload ?? const <String, dynamic>{};
    _summary =
        TextEditingController(text: payload['summary']?.toString() ?? '');
    _fields = {
      for (final key in const [
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
                  DropdownMenuItem(value: 'exercise', child: Text('运动')),
                  DropdownMenuItem(value: 'measurement', child: Text('测量')),
                ],
                onChanged: editing
                    ? null
                    : (value) => setState(() => _type = value ?? 'exercise'),
              ),
              TextField(
                controller: _summary,
                decoration: const InputDecoration(labelText: '概括'),
                maxLength: 80,
              ),
              if (_type == 'exercise') ...[
                TextField(
                  controller: _fields['exerciseType'],
                  decoration: const InputDecoration(labelText: '运动类型'),
                ),
                NumericPickerField(
                  controller: _fields['duration']!,
                  label: '时长',
                  unit: '分钟',
                  min: 5,
                  max: 300,
                  step: 5,
                  optional: true,
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
    if (_type == 'exercise') {
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

// ignore: unused_element
enum _PlanApplyMode { replace, merge }

class _PlanGoalDraft {
  const _PlanGoalDraft({
    required this.code,
    required this.detail,
    required this.targetDate,
  });

  final String code;
  final String detail;
  final DateTime? targetDate;

  String get label =>
      _planGoalOptions.firstWhere((option) => option.code == code).label;
}

class _PlanGoalOption {
  const _PlanGoalOption(this.code, this.label, this.icon);

  final String code;
  final String label;
  final IconData icon;
}

const _planGoalOptions = [
  _PlanGoalOption('improve_fitness', '增强体能', Icons.directions_run_outlined),
  _PlanGoalOption('fat_loss', '减脂塑形', Icons.monitor_weight_outlined),
  _PlanGoalOption('muscle_gain', '增强肌力', Icons.fitness_center_outlined),
  _PlanGoalOption('sleep_better', '改善睡眠', Icons.bedtime_outlined),
  _PlanGoalOption('bp_control', '管理血压', Icons.favorite_outline),
  _PlanGoalOption('glucose_control', '管理血糖', Icons.water_drop_outlined),
  _PlanGoalOption('quit_smoking', '辅助戒烟', Icons.smoke_free_outlined),
];

class _PersonalGoalCard extends StatelessWidget {
  const _PersonalGoalCard({
    required this.goal,
    required this.generating,
    required this.onCreate,
  });

  final _PlanGoalDraft? goal;
  final bool generating;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedGoal = goal;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.flag_outlined, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '你想达到什么样的状态？',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedGoal == null
                          ? '选择目标并补充你的期望，系统会结合档案和近期数据制定计划。'
                          : [
                              selectedGoal.label,
                              if (selectedGoal.detail.isNotEmpty)
                                selectedGoal.detail,
                              if (selectedGoal.targetDate != null)
                                '目标日期 ${DateFormat('yyyy年M月d日').format(selectedGoal.targetDate!)}',
                            ].join(' · '),
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCreate,
              icon: generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(
                generating
                    ? '正在制定专属计划…'
                    : selectedGoal == null
                        ? '制定我的专属计划'
                        : '调整目标并重新制定',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanGoalSheet extends StatefulWidget {
  const _PlanGoalSheet({this.initialValue});

  final _PlanGoalDraft? initialValue;

  @override
  State<_PlanGoalSheet> createState() => _PlanGoalSheetState();
}

class _PlanGoalSheetState extends State<_PlanGoalSheet> {
  late String _selectedCode;
  late DateTime? _targetDate;
  late final TextEditingController _detailController;

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.initialValue?.code ?? _planGoalOptions.first.code;
    _targetDate = widget.initialValue?.targetDate;
    _detailController = TextEditingController(
      text: widget.initialValue?.detail ?? '',
    );
  }

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: now.add(const Duration(days: 7)),
      lastDate: DateTime(now.year + 2, now.month, now.day),
      initialDate: _targetDate ?? now.add(const Duration(days: 56)),
      helpText: '选择希望达到目标状态的日期',
    );
    if (picked != null && mounted) setState(() => _targetDate = picked);
  }

  void _submit() {
    Navigator.pop(
      context,
      _PlanGoalDraft(
        code: _selectedCode,
        detail: _detailController.text.trim(),
        targetDate: _targetDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '描述你的目标状态',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '计划只包含运动、每日测量和生活习惯，不包含饮食或用药调整。',
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 18),
            Text('选择主要目标', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _planGoalOptions)
                  ChoiceChip(
                    avatar: Icon(option.icon, size: 18),
                    label: Text(option.label),
                    selected: _selectedCode == option.code,
                    onSelected: (_) =>
                        setState(() => _selectedCode = option.code),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _detailController,
              minLines: 2,
              maxLines: 4,
              maxLength: 200,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '自由补充（可选）',
                hintText: '例如：希望爬三层楼不明显气喘，每周能稳定运动4次',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colors.outlineVariant),
              ),
              leading: const Icon(Icons.event_outlined),
              title: const Text('期望达到日期（可选）'),
              subtitle: Text(
                _targetDate == null
                    ? '未设置，先制定接下来7天计划'
                    : DateFormat('yyyy年M月d日').format(_targetDate!),
              ),
              trailing: _targetDate == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      tooltip: '清除日期',
                      onPressed: () => setState(() => _targetDate = null),
                      icon: const Icon(Icons.close),
                    ),
              onTap: _pickTargetDate,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('由健康管家生成计划'),
              ),
            ),
          ],
        ),
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
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
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
                  colors.surfaceContainerLow,
                ]
              : [colors.surfaceContainerLow, colors.surfaceContainer],
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
                    child: Text('7 天运动规划',
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
                                : '档案已完善，点击生成你的 7 天运动规划。'),
                style: TextStyle(color: AppTheme.muted, height: 1.5),
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
                          Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor:
                          Theme.of(context).colorScheme.onPrimaryContainer,
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
                          ? '健康管家生成中…'
                          : aiResultReady
                              ? '查看 AI 方案'
                              : '由健康管家生成',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          );

          final rulesBox = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isCritical ? '紧急提示' : '生成规则',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (isCritical)
                  Text('请停止运动并立即就医；如有明显不适，请呼叫急救。',
                      style: TextStyle(color: AppTheme.muted, height: 1.5))
                else ...[
                  Text('· 基于档案和风险提示设定安全强度',
                      style: TextStyle(color: AppTheme.muted, height: 1.5)),
                  Text('· 运动强度：有氧 + 力量 + 恢复轮替',
                      style: TextStyle(color: AppTheme.muted, height: 1.5)),
                  Text('· 每天包含热身、主训练、放松和替代动作',
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
    final colors = Theme.of(context).colorScheme;
    final risks = _stringList(plan.payload['risks']);
    final isCritical = _isCriticalRiskPlan(plan);
    final summary = isCritical
        ? '检测到紧急健康风险，请立即就医，暂不提供健康或运动计划。'
        : plan.payload['summary']?.toString() ?? '';
    final hasRisk = risks.isNotEmpty;

    // 零风险：轻量摘要条
    if (!hasRisk) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.secondary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 16, color: colors.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                summary.isNotEmpty ? summary : '各项已录入指标均在正常范围。',
                style: TextStyle(
                    fontSize: 12,
                    color: colors.onSecondaryContainer,
                    height: 1.4),
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
        hasSevere ? colors.errorContainer : colors.tertiaryContainer;
    final borderColor =
        (hasSevere ? colors.error : colors.tertiary).withValues(alpha: 0.35);
    final iconColor =
        hasSevere ? colors.onErrorContainer : colors.onTertiaryContainer;
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
                        color: colors.surface.withValues(alpha: 0.75),
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
        ],
      ),
    );
  }
}

class _DayPlanCard extends StatelessWidget {
  const _DayPlanCard({
    required this.date,
    required this.plans,
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
  });

  final String date;
  final List<PlanRecordData> plans;
  final Future<void> Function({PlanRecordData? plan, DateTime? date}) onEdit;
  final Future<void> Function(PlanRecordData plan) onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayDate =
        DateFormat('MM月dd日').format(DateFormat('yyyy-MM-dd').parse(date));
    final exercises = plans.where((item) => item.type == 'exercise').toList();
    final measurements =
        plans.where((item) => item.type == 'measurement').toList();
    final aiPlans =
        plans.where((item) => _isAiPlanProvider(item.aiProvider)).toList();
    final isAiPlan = aiPlans.isNotEmpty;
    final provider = isAiPlan ? aiPlans.first.aiProvider : 'local';
    final sourceColor = isAiPlan ? colors.tertiary : colors.outlineVariant;

    final visibleCount = exercises.length + measurements.length;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAiPlan
              ? [
                  sourceColor.withValues(alpha: 0.12),
                  sourceColor.withValues(alpha: 0.04),
                  colors.surfaceContainerLow,
                ]
              : [colors.surfaceContainerLow, colors.surfaceContainer],
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
        key: PageStorageKey<String>('plan-day-$date'),
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
            style: TextStyle(color: colors.onSurfaceVariant)),
        children: [
          if (exercises.isNotEmpty)
            _PlanSection(
              title: '运动计划',
              icon: Icons.directions_run_outlined,
              items: exercises,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          if (measurements.isNotEmpty)
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
    final color = isAi
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onSurfaceVariant;
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
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            for (final item in items) ...[
              _ExercisePlanDetails(
                plan: item,
                onEdit: () => onEdit(plan: item),
                onDelete: () => onDelete(item),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExercisePlanDetails extends StatelessWidget {
  const _ExercisePlanDetails({
    required this.plan,
    required this.onEdit,
    required this.onDelete,
  });

  final PlanRecordData plan;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final payload = plan.payload;
    final warmup = _mapObjectList(payload['warmup']);
    final main = _mapObjectList(payload['main']);
    final cooldown = _mapObjectList(payload['cooldown']);
    final safetyNotes = _stringList(payload['safetyNotes']);
    final equipment = _stringList(payload['equipment']);
    final alternative = _asMap(payload['alternative']);
    final fallbackItems = _stringList(payload['items']);
    final structured =
        warmup.isNotEmpty || main.isNotEmpty || cooldown.isNotEmpty;
    final metadata = <String>[
      if ('${payload['durationMinutes'] ?? payload['duration'] ?? ''}'
          .isNotEmpty)
        '${payload['durationMinutes'] ?? payload['duration']} 分钟',
      if ('${payload['intensity'] ?? ''}'.isNotEmpty) '${payload['intensity']}',
      if ('${payload['location'] ?? ''}'.isNotEmpty) '${payload['location']}',
      if (equipment.isNotEmpty) equipment.join('、'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.summary,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if ('${payload['goal'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${payload['goal']}',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: '编辑计划项',
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: '删除计划项',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
            ),
          ],
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            metadata.join(' · '),
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (warmup.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AiExercisePhase(title: '热身', steps: warmup),
        ],
        if (main.isNotEmpty) ...[
          const SizedBox(height: 10),
          _AiExercisePhase(title: '主训练', steps: main),
        ],
        if (cooldown.isNotEmpty) ...[
          const SizedBox(height: 10),
          _AiExercisePhase(title: '放松拉伸', steps: cooldown),
        ],
        if (!structured)
          for (final detail in fallbackItems)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '· $detail',
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
              ),
            ),
        if (alternative.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '替代动作 · ${alternative['condition'] ?? '需要降低难度'}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            '${alternative['name'] ?? ''}：${alternative['instruction'] ?? ''}',
            style: const TextStyle(fontSize: 12, height: 1.45),
          ),
        ],
        if (safetyNotes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '安全提示',
                  style: TextStyle(
                    color: colors.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                for (final note in safetyNotes)
                  Text(
                    '· $note',
                    style: TextStyle(
                      color: colors.onTertiaryContainer,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
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
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.monitor_heart_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
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
                    Text(
                      '·  ',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Expanded(
                      child: Text(text,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.5,
                          )),
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
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.onPrimary : colors.onSurface,
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
        color: Theme.of(context).scaffoldBackgroundColor,
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 14, color: colors.onPrimaryContainer),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _aiDoctorDisclaimer,
            style: TextStyle(
              fontSize: 12,
              color: colors.onPrimaryContainer,
              height: 1.4,
            ),
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
    final colors = Theme.of(context).colorScheme;
    final weekDay = widget.day['weekDay'] as String? ?? '';
    final exercise = _asMap(widget.day['exercise']);
    final warmup = _mapObjectList(exercise['warmup']);
    final main = _mapObjectList(exercise['main']);
    final cooldown = _mapObjectList(exercise['cooldown']);
    final safetyNotes = _stringList(exercise['safetyNotes']);
    final equipment = _stringList(exercise['equipment']);
    final alternative = _asMap(exercise['alternative']);
    final measurements = _stringList(widget.day['measurements']);
    final habits = _stringList(widget.day['habits']);
    final reminders =
        (widget.day['reminders'] as List?)?.map((item) => '$item').toList() ??
            [];
    final visibleReminders = _remindersExpanded
        ? reminders
        : reminders.take(_collapsedReminderCount).toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.surfaceContainerLow,
            Theme.of(context).colorScheme.surfaceContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(weekDay,
                  style: TextStyle(
                      color: colors.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          if (exercise.isNotEmpty) ...[
            const _SectionRow(
                Icons.directions_run_outlined, '运动安排', Colors.green),
            const SizedBox(height: 8),
            Text(
              '${exercise['title'] ?? ''}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if ('${exercise['goal'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                '${exercise['goal']}',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
            const SizedBox(height: 7),
            Text(
              '${exercise['totalMinutes'] ?? 0}分钟 · '
              '${exercise['intensity'] ?? ''} · '
              '${exercise['location'] ?? ''}'
              '${equipment.isEmpty ? '' : ' · ${equipment.join('、')}'}',
              style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600),
            ),
            if (warmup.isNotEmpty) ...[
              const SizedBox(height: 12),
              _AiExercisePhase(title: '热身', steps: warmup),
            ],
            if (main.isNotEmpty) ...[
              const SizedBox(height: 10),
              _AiExercisePhase(title: '主训练', steps: main),
            ],
            if (cooldown.isNotEmpty) ...[
              const SizedBox(height: 10),
              _AiExercisePhase(title: '放松拉伸', steps: cooldown),
            ],
            if (alternative.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '替代动作 · ${alternative['condition'] ?? '需要降低难度'}',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                '${alternative['name'] ?? ''}：${alternative['instruction'] ?? ''}',
                style: const TextStyle(fontSize: 12, height: 1.45),
              ),
            ],
            if (safetyNotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '安全提示',
                      style: TextStyle(
                        color: colors.onTertiaryContainer,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final note in safetyNotes)
                      Text(
                        '· $note',
                        style: TextStyle(
                          color: colors.onTertiaryContainer,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          const _SectionRow(
            Icons.monitor_heart_outlined,
            '每日测量',
            Colors.blue,
          ),
          const SizedBox(height: 6),
          for (final item
              in measurements.isEmpty ? const ['晨起、早餐前记录体重'] : measurements)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('· $item',
                  style: const TextStyle(fontSize: 12, height: 1.45)),
            ),
          if (habits.isNotEmpty) ...[
            const SizedBox(height: 10),
            const _SectionRow(Icons.repeat_rounded, '生活习惯', Colors.teal),
            const SizedBox(height: 6),
            for (final item in habits)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('· $item',
                    style: const TextStyle(fontSize: 12, height: 1.45)),
              ),
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
                  Icon(Icons.circle, size: 5, color: colors.onSurfaceVariant),
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
}

class _AiExercisePhase extends StatelessWidget {
  const _AiExercisePhase({required this.title, required this.steps});

  final String title;
  final List<Map<String, dynamic>> steps;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 4),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                [
                  '${step['name'] ?? ''}',
                  if ((step['sets'] as num?) != null)
                    '${(step['sets'] as num).round()}组${'${step['reps'] ?? ''}'.isEmpty ? '' : ' × ${step['reps']}'}',
                  if (((step['durationMinutes'] as num?)?.toInt() ?? 0) > 0)
                    '${(step['durationMinutes'] as num).round()}分钟',
                  if (((step['restSeconds'] as num?)?.toInt() ?? 0) > 0)
                    '休息${(step['restSeconds'] as num).round()}秒',
                  '${step['instruction'] ?? ''}',
                ].where((item) => item.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 12, height: 1.45),
              ),
            ),
        ],
      );
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
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
            style: TextStyle(
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

List<Map<String, dynamic>> _mapObjectList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map(_asMap).toList();
}
