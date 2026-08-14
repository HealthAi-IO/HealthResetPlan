part of 'clock_page.dart';

class _ClockLoadingView extends StatelessWidget {
  const _ClockLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _ClockSkeletonBlock(height: 126),
        SizedBox(height: 14),
        _ClockSkeletonBlock(height: 182),
        SizedBox(height: 14),
        _ClockSkeletonBlock(height: 132),
      ],
    );
  }
}

class _SeniorClockTask {
  const _SeniorClockTask({
    required this.type,
    required this.title,
    required this.detail,
    required this.scheduledAt,
    required this.completed,
    this.skipped = false,
    this.record,
    this.reminder,
    this.plan,
  });

  final String type;
  final String title;
  final String detail;
  final DateTime scheduledAt;
  final bool completed;
  final bool skipped;
  final ClockRecordData? record;
  final ReminderData? reminder;
  final PlanRecordData? plan;

  DateTime? get completedAt => record?.clockTime;
}

class _SeniorReminderTypeTile extends StatelessWidget {
  const _SeniorReminderTypeTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.primaryBlue),
      title: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _SeniorClockView extends StatelessWidget {
  const _SeniorClockView({
    required this.tasks,
    required this.records,
    required this.waterGoalMl,
    required this.onComplete,
    required this.onChange,
    required this.onSupplement,
    required this.onManageReminders,
    required this.onRefresh,
  });

  final List<_SeniorClockTask> tasks;
  final List<ClockRecordData> records;
  final int? waterGoalMl;
  final Future<void> Function(_SeniorClockTask) onComplete;
  final Future<void> Function(_SeniorClockTask) onChange;
  final Future<void> Function() onSupplement;
  final Future<void> Function() onManageReminders;
  final Future<void> Function() onRefresh;

  Future<void> _showCompletedTasks(
    BuildContext context,
    List<_SeniorClockTask> completed,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.7,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '今天已完成',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '如记录有误，可在这里更正。',
                  style: TextStyle(fontSize: 16, color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final task in completed)
                        _SeniorCompletedTask(
                          task: task,
                          onChange: () {
                            Navigator.pop(sheetContext);
                            onChange(task);
                          },
                        ),
                    ],
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
    final pending = tasks.where((task) => !task.completed).toList();
    final completed = tasks.where((task) => task.completed).toList();
    final current = pending.firstOrNull;
    final currentTasks = current == null
        ? <_SeniorClockTask>[]
        : current.type == 'medicine'
            ? pending
                .where((task) =>
                    task.type == 'medicine' &&
                    task.scheduledAt == current.scheduledAt)
                .toList()
            : [current];
    final upcoming =
        pending.where((task) => !currentTasks.contains(task)).take(2).toList();
    final now = DateTime.now();
    final bottomPad = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('senior-clock-scroll'),
        padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPad),
        children: [
          const Text(
            '提醒',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(now),
            style: TextStyle(fontSize: 17, color: AppTheme.muted),
          ),
          _SeniorTodayTotals(records: records, waterGoalMl: waterGoalMl),
          const SizedBox(height: 18),
          if (current == null)
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                children: [
                  Icon(Icons.task_alt, color: Colors.green, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '今天的计划都完成了',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            )
          else
            _SeniorCurrentTask(
              tasks: currentTasks,
              overdue: current.scheduledAt.isBefore(now),
              onComplete: onComplete,
              onChange: onChange,
            ),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SeniorTaskSection(
              title: '接下来',
              tasks: upcoming,
              onComplete: onComplete,
              onChange: onChange,
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
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                title: Text(
                  '今天已完成 ${completed.length} 项',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text('点此更正记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showCompletedTasks(context, completed),
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onSupplement,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('补充记录'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onManageReminders,
            icon: const Icon(Icons.medication_outlined),
            label: const Text('今天的用药和提醒'),
          ),
        ],
      ),
    );
  }
}

class _SeniorCurrentTask extends StatelessWidget {
  const _SeniorCurrentTask({
    required this.tasks,
    required this.overdue,
    required this.onComplete,
    required this.onChange,
  });

  final List<_SeniorClockTask> tasks;
  final bool overdue;
  final Future<void> Function(_SeniorClockTask) onComplete;
  final Future<void> Function(_SeniorClockTask) onChange;

  @override
  Widget build(BuildContext context) {
    final task = tasks.first;
    final medicine = task.type == 'medicine';
    final multipleMedicines = medicine && tasks.length > 1;
    final warning = overdue && medicine;
    final color = warning ? Colors.redAccent : AppTheme.primaryBlue;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(warning ? Icons.error_outline : Icons.schedule,
                  color: color),
              const SizedBox(width: 8),
              Text(
                warning ? '当前任务 · 已逾时' : '当前任务',
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            DateFormat('HH:mm').format(task.scheduledAt),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(_typeIcon(task.type), size: 34, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  multipleMedicines ? '用药 · 共 ${tasks.length} 种药' : task.title,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (!multipleMedicines && task.detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(task.detail,
                style: TextStyle(fontSize: 17, color: AppTheme.muted)),
          ],
          const SizedBox(height: 18),
          if (multipleMedicines)
            for (final medicineTask in tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      medicineTask.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (medicineTask.detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          medicineTask.detail,
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.muted,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: color,
                            ),
                            onPressed: () => onComplete(medicineTask),
                            child: const Text('确认已服'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => onChange(medicineTask),
                          child: const Text('跳过'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
          else ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                minimumSize: const Size.fromHeight(62),
              ),
              onPressed: () => onComplete(task),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(medicine ? '确认已服' : '确认完成'),
            ),
            if (medicine) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => onChange(task),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('更正 / 跳过'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SeniorTaskSection extends StatelessWidget {
  const _SeniorTaskSection({
    required this.title,
    required this.tasks,
    required this.onComplete,
    required this.onChange,
  });

  final String title;
  final List<_SeniorClockTask> tasks;
  final Future<void> Function(_SeniorClockTask) onComplete;
  final Future<void> Function(_SeniorClockTask) onChange;

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
          Text(title,
              style:
                  const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(
                      DateFormat('HH:mm').format(task.scheduledAt),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(_typeIcon(task.type),
                      color: _typeColor(context, task.type)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(task.title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  FilledButton(
                    onPressed: () => onComplete(task),
                    child: Text(task.type == 'medicine' ? '已服' : '完成'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SeniorCompletedTask extends StatelessWidget {
  const _SeniorCompletedTask({required this.task, required this.onChange});

  final _SeniorClockTask task;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final time = task.completedAt == null
        ? ''
        : ' · ${DateFormat('HH:mm').format(task.completedAt!)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 10, 12),
      child: Row(
        children: [
          Icon(
            task.skipped ? Icons.remove_circle_outline : Icons.check_circle,
            color: task.skipped ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${task.title}${task.skipped ? ' · 已跳过' : time}',
              style: const TextStyle(fontSize: 17),
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('更正')),
        ],
      ),
    );
  }
}

class _ClockTarget {
  const _ClockTarget({required this.type});

  final String type;
}

_ClockTarget? _targetFromPlan(String type) {
  return switch (type) {
    'meal' => const _ClockTarget(type: 'meal'),
    'exercise' => const _ClockTarget(type: 'exercise'),
    'measurement' => const _ClockTarget(type: 'weight'),
    _ => null,
  };
}

class _ClockSkeletonBlock extends StatelessWidget {
  const _ClockSkeletonBlock({required this.height});

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

// ── 今日进度卡片 ─────────────────────────────────────────────
class _TodayProgressCard extends StatelessWidget {
  const _TodayProgressCard({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final rate = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final pct = (rate * 100).round();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '今日打卡进度',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '$done / $total 条完成',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: rate,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$pct%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 打卡按钮 ─────────────────────────────────────────────────
class _ClockTile extends StatelessWidget {
  const _ClockTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 提醒快捷芯片 ──────────────────────────────────────────────
class _ReminderChip extends StatelessWidget {
  const _ReminderChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppTheme.deepBlue),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      side: BorderSide(color: AppTheme.cardBorder),
      labelStyle: TextStyle(
        color: AppTheme.deepBlue,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    );
  }
}

// ── 打卡记录列表 ──────────────────────────────────────────────
class _RecordList extends StatelessWidget {
  const _RecordList({
    required this.records,
    required this.onEdit,
    required this.onDelete,
    required this.onCorrectMedicine,
  });
  final List<ClockRecordData> records;
  final ValueChanged<ClockRecordData> onEdit;
  final ValueChanged<ClockRecordData> onDelete;
  final VoidCallback onCorrectMedicine;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '暂无打卡记录，点击上方按钮开始打卡。',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }
    return Column(
      children: [
        for (final r in records)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color:
                          _typeColor(context, r.type).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _typeIcon(r.type),
                      color: _typeColor(context, r.type),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${r.label}  ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            if (r.status == 'skip')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '跳过',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          r.displayDetail.isNotEmpty
                              ? r.displayDetail
                              : DateFormat('MM月dd日 HH:mm').format(r.clockTime),
                          style: TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '记录操作',
                    onSelected: (value) {
                      if (value == 'correct') {
                        onCorrectMedicine();
                      } else if (value == 'edit') {
                        onEdit(r);
                      } else {
                        onDelete(r);
                      }
                    },
                    itemBuilder: (_) => [
                      if (r.type == 'medicine')
                        const PopupMenuItem(
                          value: 'correct',
                          child: Text('更正用药'),
                        )
                      else ...[
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('更正记录'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除记录'),
                        ),
                      ],
                    ],
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                      child: Text(
                        DateFormat('HH:mm').format(r.clockTime),
                        style: TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TodayRecordSummary extends StatelessWidget {
  const _TodayRecordSummary({
    required this.records,
    required this.waterGoalMl,
    required this.medicineScheduledCount,
    required this.medicineTakenCount,
    required this.onViewAll,
  });

  final List<ClockRecordData> records;
  final int? waterGoalMl;
  final int medicineScheduledCount;
  final int medicineTakenCount;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '今天还没有打卡记录。',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }
    const order = ['meal', 'exercise', 'medicine', 'weight', 'water'];
    final groups = <String, List<ClockRecordData>>{};
    for (final record in records) {
      groups.putIfAbsent(record.type, () => []).add(record);
    }
    final visibleTypes = order.where(groups.containsKey);

    return Column(
      children: [
        for (final type in visibleTypes)
          _TodayRecordSummaryRow(
            type: type,
            records: groups[type]!,
            waterGoalMl: waterGoalMl,
            medicineScheduledCount: medicineScheduledCount,
            medicineTakenCount: medicineTakenCount,
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onViewAll,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('查看今天全部记录'),
          ),
        ),
      ],
    );
  }
}

class _TodayRecordSummaryRow extends StatelessWidget {
  const _TodayRecordSummaryRow({
    required this.type,
    required this.records,
    required this.waterGoalMl,
    required this.medicineScheduledCount,
    required this.medicineTakenCount,
  });

  final String type;
  final List<ClockRecordData> records;
  final int? waterGoalMl;
  final int medicineScheduledCount;
  final int medicineTakenCount;

  @override
  Widget build(BuildContext context) {
    final latest = records.first;
    final completed =
        records.where((record) => record.status == 'done').toList();
    final waterTotal = _waterTotalFor(completed);
    final exerciseTotal = _exerciseTotalFor(completed);
    final mealNames = completed
        .map((record) => record.mealName)
        .where((name) => name.isNotEmpty)
        .toSet()
        .join('、');
    final mealCalories = completed.fold<int>(
      0,
      (total, record) => total + (record.mealCalories ?? 0),
    );
    final summary = switch (type) {
      'medicine' when medicineScheduledCount > 0 =>
        '已服 $medicineTakenCount/$medicineScheduledCount 次',
      'weight' when latest.note.isNotEmpty => latest.note,
      'meal' when mealNames.isNotEmpty && mealCalories > 0 =>
        '$mealNames · 共 $mealCalories kcal',
      'meal' when mealNames.isNotEmpty => '今天已记录 $mealNames',
      'water' when waterTotal > 0 && waterGoalMl != null =>
        '今日 ${completed.length} 次 · $waterTotal/$waterGoalMl ml · ${(waterTotal / waterGoalMl! * 100).clamp(0, 999).round()}%',
      'water' when waterTotal > 0 =>
        '今日 ${completed.length} 次 · 共 $waterTotal ml',
      'exercise' when exerciseTotal > 0 =>
        '${latest.displayDetail} · 今日共 $exerciseTotal 分钟',
      _ => '今天 ${records.length} 次',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _typeColor(context, type).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child:
            Icon(_typeIcon(type), color: _typeColor(context, type), size: 21),
      ),
      title: Text(
        latest.label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        DateFormat('HH:mm').format(latest.clockTime),
        style: TextStyle(color: AppTheme.muted),
      ),
    );
  }
}

class _TodayRecordTotals extends StatelessWidget {
  const _TodayRecordTotals({
    required this.records,
    required this.waterGoalMl,
  });

  final List<ClockRecordData> records;
  final int? waterGoalMl;

  @override
  Widget build(BuildContext context) {
    final completed =
        records.where((record) => record.status == 'done').toList();
    final waterTotal = _waterTotalFor(completed);
    final exerciseTotal = _exerciseTotalFor(completed);
    if (waterTotal == 0 && exerciseTotal == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (waterTotal > 0)
            _RecordTotalChip(
              icon: Icons.water_drop_outlined,
              text: waterGoalMl == null
                  ? '今日饮水 $waterTotal ml'
                  : '今日饮水 $waterTotal / $waterGoalMl ml',
              color: AppTheme.water(context),
            ),
          if (exerciseTotal > 0)
            _RecordTotalChip(
              icon: Icons.directions_run_outlined,
              text: '今日运动 $exerciseTotal 分钟',
              color: AppTheme.exercise(context),
            ),
        ],
      ),
    );
  }
}

class _RecordTotalChip extends StatelessWidget {
  const _RecordTotalChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(width: 7),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _SeniorTodayTotals extends StatelessWidget {
  const _SeniorTodayTotals({required this.records, required this.waterGoalMl});

  final List<ClockRecordData> records;
  final int? waterGoalMl;

  @override
  Widget build(BuildContext context) {
    final completed =
        records.where((record) => record.status == 'done').toList();
    final waterTotal = _waterTotalFor(completed);
    final exerciseTotal = _exerciseTotalFor(completed);
    if (waterTotal == 0 && exerciseTotal == 0) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            if (waterTotal > 0)
              ListTile(
                minTileHeight: 72,
                leading: const Icon(Icons.water_drop_outlined, size: 32),
                title: const Text('今天喝水', style: TextStyle(fontSize: 18)),
                subtitle: Text(
                  waterGoalMl == null
                      ? '$waterTotal 毫升'
                      : '$waterTotal / $waterGoalMl 毫升',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
            if (waterTotal > 0 && exerciseTotal > 0) const Divider(height: 1),
            if (exerciseTotal > 0)
              ListTile(
                minTileHeight: 72,
                leading: const Icon(Icons.directions_walk_outlined, size: 32),
                title: const Text('今天运动', style: TextStyle(fontSize: 18)),
                subtitle: Text(
                  '$exerciseTotal 分钟',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

int _waterTotalFor(Iterable<ClockRecordData> records) => records.fold(
      0,
      (total, record) => total + (record.waterMilliliters ?? 0),
    );

int _exerciseTotalFor(Iterable<ClockRecordData> records) => records.fold(
      0,
      (total, record) => total + (record.exerciseMinutes ?? 0),
    );

// ── 提醒规则列表 ──────────────────────────────────────────────
class _ReminderList extends StatefulWidget {
  const _ReminderList({
    required this.reminders,
    required this.onDelete,
    required this.onEdit,
    required this.onToggle,
    required this.onResync,
    required this.onSyncAlarm,
    required this.onOpen,
  });
  final List<ReminderData> reminders;
  final Future<void> Function(ReminderData) onDelete;
  final Future<void> Function(ReminderData) onEdit;
  final Future<void> Function(ReminderData) onToggle;
  final Future<void> Function(ReminderData) onResync;
  final Future<void> Function(ReminderData) onSyncAlarm;
  final Future<void> Function(ReminderData) onOpen;

  @override
  State<_ReminderList> createState() => _ReminderListState();
}

class _ReminderListState extends State<_ReminderList> {
  static const _collapsedCount = 4;
  bool _expanded = false;
  int? _expandedActionReminderId;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final reminders = widget.reminders.where((item) {
      return item.occursOn(now) &&
          item.dailyTimes.any(
            (time) => DateTime(
              now.year,
              now.month,
              now.day,
              time.hour,
              time.minute,
            ).isAfter(now),
          );
    }).toList()
      ..sort((a, b) {
        if (a.isEnabled != b.isEnabled) return a.isEnabled ? -1 : 1;
        final aMinutes = a.remindTime.hour * 60 + a.remindTime.minute;
        final bMinutes = b.remindTime.hour * 60 + b.remindTime.minute;
        return aMinutes.compareTo(bMinutes);
      });

    if (reminders.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('今天暂无提醒。', style: TextStyle(color: AppTheme.muted)),
          ),
          const _ReminderSafetyNotice(),
        ],
      );
    }
    final visible = _expanded
        ? reminders
        : reminders.take(_collapsedCount).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...visible.map(_buildReminder),
        if (reminders.length > _collapsedCount)
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              ),
              label: Text(_expanded ? '收起提醒' : '展开全部 ${reminders.length} 条'),
            ),
          ),
        const _ReminderSafetyNotice(),
      ],
    );
  }

  Widget _buildReminder(ReminderData reminder) {
    final now = DateTime.now();
    final timeText = reminder.dailyTimes
        .where(
          (time) => DateTime(
            now.year,
            now.month,
            now.day,
            time.hour,
            time.minute,
          ).isAfter(now),
        )
        .map((time) =>
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')
        .join('、');
    final imageObjectKey = reminder.payload['imageObjectKey']?.toString() ?? '';
    final imageProvider = reportImageProvider(imageObjectKey);
    final showActions =
        reminder.id != null && _expandedActionReminderId == reminder.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: () => widget.onOpen(reminder),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: imageProvider == null
                          ? Icon(
                              Icons.notifications_active_outlined,
                              color: AppTheme.deepBlue,
                              size: 19,
                            )
                          : Image(
                              image: imageProvider,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.medication_outlined,
                                color: AppTheme.deepBlue,
                                size: 19,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  reminder.displayLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (!reminder.isEnabled)
                                Text(
                                  '已暂停',
                                  style: TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            '今天 $timeText · ${_reminderSourceText(reminder)} · ${reminder.type == 'medicine' ? _medicineDoseSummary(reminder) : reminder.payload['note'] as String? ?? reminder.label}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: reminder.isEnabled
                                  ? AppTheme.muted
                                  : AppTheme.muted.withValues(alpha: 0.65),
                              fontSize: 12,
                            ),
                          ),
                          if (reminder.refillNeeded)
                            Text(
                              '库存不足，请及时补充',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: showActions ? '收起操作' : '更多操作',
                      onPressed: () => setState(() {
                        _expandedActionReminderId =
                            showActions ? null : reminder.id;
                      }),
                      icon: AnimatedRotation(
                        turns: showActions ? 0.25 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.more_vert),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: showActions
                  ? _ReminderActionBar(
                      enabled: reminder.isEnabled,
                      onToggle: () async {
                        setState(() => _expandedActionReminderId = null);
                        await widget.onToggle(reminder);
                      },
                      onEdit: reminder.channel == 'local'
                          ? () async {
                              setState(() => _expandedActionReminderId = null);
                              await widget.onEdit(reminder);
                            }
                          : null,
                      onResync: () async {
                        setState(() => _expandedActionReminderId = null);
                        await widget.onResync(reminder);
                      },
                      onSyncAlarm:
                          defaultTargetPlatform == TargetPlatform.android &&
                                  reminder.type == 'medicine' &&
                                  reminder.isWeekly
                              ? () async {
                                  setState(
                                    () => _expandedActionReminderId = null,
                                  );
                                  await widget.onSyncAlarm(reminder);
                                }
                              : null,
                      onDelete: () async {
                        setState(() => _expandedActionReminderId = null);
                        await widget.onDelete(reminder);
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderActionBar extends StatelessWidget {
  const _ReminderActionBar({
    required this.enabled,
    required this.onToggle,
    required this.onEdit,
    required this.onResync,
    required this.onSyncAlarm,
    required this.onDelete,
  });

  final bool enabled;
  final Future<void> Function()? onToggle;
  final Future<void> Function()? onEdit;
  final Future<void> Function() onResync;
  final Future<void> Function()? onSyncAlarm;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        border: Border(top: BorderSide(color: AppTheme.cardBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 4,
          runSpacing: 2,
          children: [
            if (onToggle != null)
              TextButton.icon(
                onPressed: onToggle,
                icon: Icon(
                  enabled ? Icons.pause_outlined : Icons.play_arrow_outlined,
                  size: 18,
                ),
                label: Text(enabled ? '暂停' : '恢复'),
              ),
            if (onEdit != null)
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑'),
              ),
            TextButton.icon(
              onPressed: onResync,
              icon: const Icon(Icons.sync_outlined, size: 18),
              label: const Text('重新同步'),
            ),
            if (onSyncAlarm != null)
              TextButton.icon(
                onPressed: onSyncAlarm,
                icon: const Icon(Icons.alarm_add_outlined, size: 18),
                label: const Text('同步闹钟'),
              ),
            TextButton.icon(
              onPressed: onDelete,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderSafetyNotice extends StatelessWidget {
  const _ReminderSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.muted),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'APP 提醒可能受系统限制产生延迟，不用于紧急或关键医疗用途。',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 面板容器 ──────────────────────────────────────────────────
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.surfaceContainerLow,
            Theme.of(context).colorScheme.surfaceContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.deepBlue.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── 提醒弹窗 ──────────────────────────────────────────────────
class _MedicineTimeDraft {
  const _MedicineTimeDraft({
    required this.time,
    required this.dose,
    required this.instructions,
  });

  final TimeOfDay time;
  final String dose;
  final String instructions;

  _MedicineTimeDraft copyWith({
    TimeOfDay? time,
    String? dose,
    String? instructions,
  }) {
    return _MedicineTimeDraft(
      time: time ?? this.time,
      dose: dose ?? this.dose,
      instructions: instructions ?? this.instructions,
    );
  }
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.type, this.reminder});
  final String type;
  final ReminderData? reminder;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  final _noteCtrl = TextEditingController();
  final _strengthCtrl = TextEditingController();
  final _inventoryCtrl = TextEditingController();
  final _refillThresholdCtrl = TextEditingController();
  final _imagePicker = ImagePicker();
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  List<_MedicineTimeDraft> _medicineTimes = const [
    _MedicineTimeDraft(
      time: TimeOfDay(hour: 7, minute: 0),
      dose: '1 片',
      instructions: '',
    ),
  ];
  late DateTime _date;
  DateTime? _courseEndDate;
  String _scheduleMode = 'weekly';
  Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  XFile? _image;
  String? _imageError;
  bool _removeExistingImage = false;
  late bool _syncAlarm;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    final reminder = widget.reminder;
    if (reminder != null) {
      _time = TimeOfDay.fromDateTime(reminder.remindTime);
      _date = reminder.startDate;
      _scheduleMode = reminder.isWeekly ? 'weekly' : 'once';
      _weekdays = reminder.weekdays.toSet();
      _noteCtrl.text = reminder.payload['note']?.toString() ?? '';
      _medicineTimes = reminder.dailyTimes
          .map((time) => _MedicineTimeDraft(
                time: TimeOfDay(hour: time.hour, minute: time.minute),
                dose: reminder.doseAt(time),
                instructions: reminder.instructionsAt(time),
              ))
          .toList();
      _strengthCtrl.text = reminder.payload['strength']?.toString() ?? '';
      _inventoryCtrl.text =
          reminder.inventoryRemaining?.toStringAsFixed(0) ?? '';
      _refillThresholdCtrl.text =
          reminder.refillThreshold?.toStringAsFixed(0) ?? '';
      _courseEndDate = reminder.courseEndDate;
    }
    _syncAlarm = reminder?.payload['syncAlarm'] == true ||
        (reminder == null &&
            widget.type == 'medicine' &&
            defaultTargetPlatform == TargetPlatform.android);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _strengthCtrl.dispose();
    _inventoryCtrl.dispose();
    _refillThresholdCtrl.dispose();
    super.dispose();
  }

  String get _title => switch (widget.type) {
        'meal' => '饮食提醒',
        'exercise' => '运动提醒',
        'medicine' => '用药提醒',
        'weight' => '称重提醒',
        'water' => '饮水提醒',
        _ => '提醒',
      };

  String get _existingImageObjectKey =>
      widget.reminder?.payload['imageObjectKey']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.reminder == null ? '新增$_title' : '编辑$_title'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _noteCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.type == 'medicine' ? '药品名称' : '备注（选填）',
                ),
              ),
              if (widget.type == 'medicine') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _strengthCtrl,
                  decoration: const InputDecoration(
                    labelText: '药品规格（选填）',
                    hintText: '例如 10mg/片',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('单次提醒'),
                      selected: _scheduleMode == 'once',
                      onSelected: (_) => setState(() {
                        _scheduleMode = 'once';
                        _syncAlarm = false;
                        final selectedTime = widget.type == 'medicine'
                            ? _medicineTimes.first.time
                            : _time;
                        final at = DateTime(
                          _date.year,
                          _date.month,
                          _date.day,
                          selectedTime.hour,
                          selectedTime.minute,
                        );
                        if (!at.isAfter(DateTime.now())) {
                          _date = _date.add(const Duration(days: 1));
                        }
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('每周重复'),
                      selected: _scheduleMode == 'weekly',
                      onSelected: (_) =>
                          setState(() => _scheduleMode = 'weekly'),
                    ),
                  ],
                ),
              ),
              if (_scheduleMode == 'once')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('提醒日期'),
                  subtitle: Text(_dateText(_date)),
                  trailing: TextButton(
                    onPressed: _pickDate,
                    child: const Text('选择'),
                  ),
                ),
              if (_scheduleMode == 'weekly') ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        ChoiceChip(
                          label: Text(_weekdayShort(day)),
                          selected: _weekdays.contains(day),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _weekdays.add(day);
                            } else {
                              _weekdays.remove(day);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => setState(
                          () => _weekdays = {1, 2, 3, 4, 5, 6, 7},
                        ),
                        child: const Text('每天'),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _weekdays = {1, 2, 3, 4, 5}),
                        child: const Text('工作日'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _weekdays = {6, 7}),
                        child: const Text('周末'),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.type == 'medicine') ...[
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '疗程结束日期（选填）',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _courseEndDate == null
                            ? '未设置'
                            : _dateText(_courseEndDate!),
                      ),
                    ),
                    if (_courseEndDate != null)
                      IconButton(
                        tooltip: '清除',
                        onPressed: () => setState(() => _courseEndDate = null),
                        icon: const Icon(Icons.clear),
                      ),
                    TextButton(
                      onPressed: _pickCourseEndDate,
                      child: const Text('选择'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                NumericPickerField(
                  controller: _inventoryCtrl,
                  label: '剩余服用次数（选填）',
                  min: 0,
                  max: 10000,
                  step: 1,
                  optional: true,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                NumericPickerField(
                  controller: _refillThresholdCtrl,
                  label: '补药提醒阈值（选填）',
                  min: 0,
                  max: 10000,
                  step: 1,
                  optional: true,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.android)
                        OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('拍照'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          kIsWeb ||
                                  defaultTargetPlatform ==
                                      TargetPlatform.windows
                              ? '选择图片'
                              : '从相册选择',
                        ),
                      ),
                      if (_image != null ||
                          (_existingImageObjectKey.isNotEmpty &&
                              !_removeExistingImage))
                        TextButton(
                          onPressed: () => setState(() {
                            _image = null;
                            _removeExistingImage = true;
                            _imageError = null;
                          }),
                          child: const Text('移除'),
                        ),
                    ],
                  ),
                ),
                if (_image != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FutureBuilder<Uint8List>(
                      future: _image!.readAsBytes(),
                      builder: (context, snapshot) {
                        final bytes = snapshot.data;
                        if (bytes == null) {
                          return const SizedBox(
                            height: 120,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return Image.memory(
                          bytes,
                          width: double.infinity,
                          height: 140,
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                  ),
                ] else if (_existingImageObjectKey.isNotEmpty &&
                    !_removeExistingImage) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image(
                      image: reportImageProvider(_existingImageObjectKey)!,
                      width: double.infinity,
                      height: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 120,
                        child: Center(child: Text('药品图片加载失败')),
                      ),
                    ),
                  ),
                ],
                if (_imageError != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _imageError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              if (widget.type == 'medicine')
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '服药时间和剂量',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '每个时间点可以设置不同剂量和用法',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      for (var index = 0;
                          index < _medicineTimes.length;
                          index++)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.only(left: 12, right: 4),
                            title: Text(
                              _medicineTimes[index].time.format(context),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text([
                              _medicineTimes[index].dose,
                              _medicineTimes[index].instructions,
                            ].where((value) => value.isNotEmpty).join(' · ')),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  tooltip: '编辑时间和剂量',
                                  onPressed: () => _editMedicineTime(index),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                if (_medicineTimes.length > 1)
                                  IconButton(
                                    tooltip: '删除这个时间',
                                    onPressed: () => setState(
                                      () => _medicineTimes.removeAt(index),
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: _addMedicineTime,
                        icon: const Icon(Icons.add),
                        label: const Text('添加服药时间'),
                      ),
                    ],
                  ),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('提醒时间'),
                  subtitle: Text(_time.format(context)),
                  trailing: TextButton(
                    onPressed: _pickTime,
                    child: const Text('选择'),
                  ),
                ),
              if (defaultTargetPlatform == TargetPlatform.android &&
                  widget.type == 'medicine' &&
                  _scheduleMode == 'weekly') ...[
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('同步到手机闹钟', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '将该时间写入系统时钟App',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _syncAlarm,
                  onChanged: (v) => setState(() => _syncAlarm = v),
                ),
              ],
              if (widget.type == 'medicine')
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '建议同步到系统闹钟，确保准时提醒。APP 提醒不用于紧急或关键医疗用途。',
                    style: TextStyle(fontSize: 12, color: AppTheme.ink),
                  ),
                ),
              if (_validationMessage != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _validationMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
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
          onPressed: _validationMessage == null ? _save : null,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _pickCourseEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _courseEndDate ?? _date,
      firstDate: _date,
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (picked != null && mounted) setState(() => _courseEndDate = picked);
  }

  Future<void> _addMedicineTime() async {
    if (_medicineTimes.length >= 6) return;
    final draft = await _showMedicineTimeEditor(
      _MedicineTimeDraft(
        time: _medicineTimes.last.time,
        dose: _medicineTimes.last.dose,
        instructions: _medicineTimes.last.instructions,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _medicineTimes = [..._medicineTimes, draft]..sort((a, b) =>
          (a.time.hour * 60 + a.time.minute)
              .compareTo(b.time.hour * 60 + b.time.minute));
    });
  }

  Future<void> _editMedicineTime(int index) async {
    final draft = await _showMedicineTimeEditor(_medicineTimes[index]);
    if (draft == null || !mounted) return;
    setState(() {
      _medicineTimes[index] = draft;
      _medicineTimes.sort((a, b) => (a.time.hour * 60 + a.time.minute)
          .compareTo(b.time.hour * 60 + b.time.minute));
    });
  }

  Future<_MedicineTimeDraft?> _showMedicineTimeEditor(
    _MedicineTimeDraft initial,
  ) async {
    var selectedTime = initial.time;
    final doseController = TextEditingController(text: initial.dose);
    final instructionsController =
        TextEditingController(text: initial.instructions);
    try {
      return await showDialog<_MedicineTimeDraft>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('服药时间和剂量'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('服药时间'),
                  subtitle: Text(selectedTime.format(context)),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                    child: const Text('选择'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: doseController,
                  decoration: const InputDecoration(
                    labelText: '本次剂量',
                    hintText: '例如 1 片',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: instructionsController,
                  decoration: const InputDecoration(
                    labelText: '本次用法（选填）',
                    hintText: '例如 饭后服用',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final dose = doseController.text.trim();
                  if (dose.isEmpty) return;
                  Navigator.pop(
                    dialogContext,
                    initial.copyWith(
                      time: selectedTime,
                      dose: dose,
                      instructions: instructionsController.text.trim(),
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
    } finally {
      await Future<void>.delayed(kThemeAnimationDuration);
      doseController.dispose();
      instructionsController.dispose();
    }
  }

  String? get _validationMessage {
    if (widget.type == 'medicine') {
      if (_noteCtrl.text.trim().isEmpty) return '请输入药品名称';
      if (_medicineTimes.any((item) => item.dose.trim().isEmpty)) {
        return '请为每个服药时间填写剂量';
      }
      final timeKeys = _medicineTimes
          .map((item) => '${item.time.hour}:${item.time.minute}')
          .toSet();
      if (timeKeys.length != _medicineTimes.length) {
        return '服药时间不能重复';
      }
      if (_courseEndDate != null && _courseEndDate!.isBefore(_date)) {
        return '疗程结束日期不能早于开始日期';
      }
      final inventory = double.tryParse(_inventoryCtrl.text.trim());
      final threshold = double.tryParse(_refillThresholdCtrl.text.trim());
      if (_inventoryCtrl.text.trim().isNotEmpty &&
          (inventory == null || inventory < 0)) {
        return '剩余服用次数必须为非负数字';
      }
      if (_refillThresholdCtrl.text.trim().isNotEmpty &&
          (threshold == null || threshold < 0)) {
        return '补药提醒阈值必须为非负数字';
      }
      if (inventory != null && threshold != null && threshold > inventory) {
        return '补药提醒阈值不能大于当前剩余次数';
      }
    }
    if (_scheduleMode == 'weekly' && _weekdays.isEmpty) {
      return '请至少选择一个提醒星期';
    }
    if (_scheduleMode == 'once') {
      final primaryTime =
          widget.type == 'medicine' ? _medicineTimes.first.time : _time;
      final at = DateTime(
        _date.year,
        _date.month,
        _date.day,
        primaryTime.hour,
        primaryTime.minute,
      );
      if (!at.isAfter(DateTime.now())) return '单次提醒时间必须晚于当前时间';
    }
    return null;
  }

  void _save() {
    final primaryTime =
        widget.type == 'medicine' ? _medicineTimes.first.time : _time;
    final inventory = double.tryParse(_inventoryCtrl.text.trim());
    final threshold = double.tryParse(_refillThresholdCtrl.text.trim());
    Navigator.pop(
      context,
      _ReminderDraft(
        time: TimeOfDayValue(
          hour: primaryTime.hour,
          minute: primaryTime.minute,
        ),
        date: _date,
        scheduleMode: _scheduleMode,
        weekdays: _weekdays.toList()..sort(),
        note: _noteCtrl.text.trim().isEmpty ? _title : _noteCtrl.text.trim(),
        syncAlarm: _scheduleMode == 'weekly' && _syncAlarm,
        image: _image,
        imageMimeType: _imageMimeType(_image),
        removeExistingImage: _removeExistingImage,
        payloadExtras: widget.type == 'medicine'
            ? {
                'medicineName': _noteCtrl.text.trim(),
                'strength': _strengthCtrl.text.trim(),
                'dose': _medicineTimes.first.dose,
                'instructions': _medicineTimes.first.instructions,
                'dailyTimes': _medicineTimes
                    .map((item) => {
                          'hour': item.time.hour,
                          'minute': item.time.minute,
                        })
                    .toList(),
                'doseByTime': {
                  for (final item in _medicineTimes)
                    '${item.time.hour.toString().padLeft(2, '0')}:${item.time.minute.toString().padLeft(2, '0')}':
                        item.dose,
                },
                'instructionsByTime': {
                  for (final item in _medicineTimes)
                    if (item.instructions.isNotEmpty)
                      '${item.time.hour.toString().padLeft(2, '0')}:${item.time.minute.toString().padLeft(2, '0')}':
                          item.instructions,
                },
                if (_courseEndDate != null)
                  'courseEndAt': DateTime(
                    _courseEndDate!.year,
                    _courseEndDate!.month,
                    _courseEndDate!.day,
                  ).millisecondsSinceEpoch,
                if (inventory != null) 'inventoryRemaining': inventory,
                if (threshold != null) 'refillThreshold': threshold,
                'archived': false,
              }
            : const {},
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (image == null) return;
    final extension = image.name.toLowerCase().split('.').last;
    if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
      if (mounted) setState(() => _imageError = '仅支持 JPG、PNG 或 WebP 图片');
      return;
    }
    if (await image.length() > 5 * 1024 * 1024) {
      if (mounted) setState(() => _imageError = '图片不能超过 5MB');
      return;
    }
    if (mounted) {
      setState(() {
        _image = image;
        _removeExistingImage = false;
        _imageError = null;
      });
    }
  }
}

class _ReminderDraft {
  const _ReminderDraft({
    required this.time,
    required this.date,
    required this.scheduleMode,
    required this.weekdays,
    required this.note,
    this.syncAlarm = false,
    this.image,
    this.imageMimeType = '',
    this.removeExistingImage = false,
    this.payloadExtras = const {},
  });
  final TimeOfDayValue time;
  final DateTime date;
  final String scheduleMode;
  final List<int> weekdays;
  final String note;
  final bool syncAlarm;
  final XFile? image;
  final String imageMimeType;
  final bool removeExistingImage;
  final Map<String, Object?> payloadExtras;
}

class _ReminderDetailsDialog extends StatelessWidget {
  const _ReminderDetailsDialog({required this.reminder});

  final ReminderData reminder;

  @override
  Widget build(BuildContext context) {
    final note = reminder.payload['note']?.toString() ?? reminder.label;
    final imageObjectKey = reminder.payload['imageObjectKey']?.toString() ?? '';
    final imageProvider = reportImageProvider(imageObjectKey);
    return AlertDialog(
      title: Text(reminder.label),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageProvider != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image(
                    image: imageProvider,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 180,
                      child: Center(child: Text('药品图片加载失败')),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                _reminderScheduleText(reminder),
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Text(note),
              if (reminder.type == 'medicine') ...[
                const SizedBox(height: 10),
                if ((reminder.payload['strength']?.toString() ?? '').isNotEmpty)
                  Text('规格：${reminder.payload['strength']}'),
                const SizedBox(height: 6),
                for (final time in reminder.dailyTimes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}  ${[
                        reminder.doseAt(time),
                        reminder.instructionsAt(time),
                      ].where((value) => value.isNotEmpty).join(' · ')}',
                    ),
                  ),
                if (reminder.inventoryRemaining != null)
                  Text(
                      '剩余库存：${reminder.inventoryRemaining!.toStringAsFixed(0)}'),
                if (reminder.courseEndDate != null)
                  Text(
                    '疗程结束：${DateFormat('yyyy-MM-dd').format(reminder.courseEndDate!)}',
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (reminder.channel == 'local')
          TextButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('编辑'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

String _medicineDoseSummary(ReminderData reminder) {
  final values = reminder.dailyTimes
      .map((time) => reminder.doseAt(time))
      .where((value) => value.isNotEmpty)
      .toSet();
  if (values.isEmpty) return '按医嘱服用';
  return values.length == 1 ? values.first : '各时间剂量不同';
}

String _imageMimeType(XFile? image) {
  if (image == null) return '';
  final provided = image.mimeType;
  if (provided != null && provided.isNotEmpty) return provided;
  final extension = image.name.toLowerCase().split('.').last;
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => '',
  };
}

String _weekdayShort(int weekday) => switch (weekday) {
      1 => '一',
      2 => '二',
      3 => '三',
      4 => '四',
      5 => '五',
      6 => '六',
      7 => '日',
      _ => '',
    };

String _dateText(DateTime date) {
  return '${date.year}年${date.month}月${date.day}日 周${_weekdayShort(date.weekday)}';
}

String _weekdaysText(List<int> weekdays) {
  if (weekdays.length == 7) return '每天';
  if (weekdays.join(',') == '1,2,3,4,5') return '工作日';
  if (weekdays.join(',') == '6,7') return '周末';
  return weekdays.map((day) => '周${_weekdayShort(day)}').join('、');
}

String _reminderScheduleText(ReminderData reminder) {
  final times = reminder.dailyTimes
      .map((time) =>
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')
      .join('、');
  if (!reminder.isWeekly) {
    return '${_dateText(reminder.remindTime)} $times';
  }
  return '${_weekdaysText(reminder.weekdays)} $times';
}

String _reminderSourceText(ReminderData reminder) => switch (reminder.source) {
      'manual' => '手动创建',
      'ai-plan' => 'AI 计划',
      'risk' => '风险建议',
      _ => '计划提醒',
    };

// ── 工具函数 ──────────────────────────────────────────────────
IconData _typeIcon(String type) => switch (type) {
      'meal' => Icons.restaurant_outlined,
      'exercise' => Icons.directions_run_outlined,
      'medicine' => Icons.medication_outlined,
      'weight' => Icons.scale_outlined,
      'water' => Icons.water_drop_outlined,
      'quit_smoking' => Icons.smoke_free_outlined,
      _ => Icons.check_circle_outline,
    };

Color _typeColor(BuildContext context, String type) => switch (type) {
      'meal' => AppTheme.meal(context),
      'exercise' => AppTheme.exercise(context),
      'medicine' => AppTheme.medicine(context),
      'weight' => AppTheme.weight(context),
      'water' => AppTheme.water(context),
      'quit_smoking' => Theme.of(context).colorScheme.tertiary,
      _ => Theme.of(context).colorScheme.primary,
    };

class _QuickClockSheet extends StatelessWidget {
  const _QuickClockSheet({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
