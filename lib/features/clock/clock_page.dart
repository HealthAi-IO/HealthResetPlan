import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';

class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  final HealthRepository _repo = sl<HealthRepository>();

  bool _loading = true;
  List<ClockRecordData> _records = const [];
  List<ReminderData> _reminders = const [];

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
    final records = await _repo.loadClockRecords(limit: 30);
    final reminders = await _repo.loadReminders();
    if (!mounted) return;
    setState(() {
      _records = records;
      _reminders = reminders;
      _loading = false;
    });
  }

  Future<void> _clock(String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final note = await _showNoteDialog(
      title: _clockTitle(type),
      hint: '可填写备注，例如“低盐便当”“饭后散步 20 分钟”。',
    );
    if (note == null) return;
    await _repo.addClockRecord(type: type, note: note);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('打卡已保存到本地')));
  }

  Future<void> _addReminder(String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_ReminderDraft>(
      context: context,
      builder: (_) => _ReminderDialog(type: type),
    );
    if (result == null) return;
    await _repo.addReminder(type: type, time: result.time, note: result.note);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('提醒规则已保存到本地')));
  }

  Future<String?> _showNoteDialog(
      {required String title, required String hint}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final todayCount = _records.where((record) {
      final time = record.clockTime;
      final now = DateTime.now();
      return time.year == now.year &&
          time.month == now.month &&
          time.day == now.day;
    }).length;
    final bottomPadding =
        MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
        children: [
          _Panel(
            title: '快速打卡',
            subtitle: '记录当前行为，形成可追溯的本地日志',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: columns >= 4 ? 1.5 : 1.08,
                  children: [
                    _ActionTile(
                      icon: Icons.restaurant_outlined,
                      label: '饮食',
                      onTap: () => _clock('meal'),
                    ),
                    _ActionTile(
                      icon: Icons.directions_run_outlined,
                      label: '运动',
                      onTap: () => _clock('exercise'),
                    ),
                    _ActionTile(
                      icon: Icons.medication_outlined,
                      label: '用药',
                      onTap: () => _clock('medicine'),
                    ),
                    _ActionTile(
                      icon: Icons.scale_outlined,
                      label: '称重',
                      onTap: () => _clock('weight'),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 4 : 2;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: columns >= 4 ? 1.55 : 1.45,
                children: [
                  _MetricCard(title: '今日打卡', value: '$todayCount 次'),
                  _MetricCard(title: '提醒规则', value: '${_reminders.length} 条'),
                  _MetricCard(
                      title: '最近记录',
                      value: _records.isEmpty
                          ? '--'
                          : DateFormat('MM/dd')
                              .format(_records.first.clockTime)),
                  _MetricCard(title: '本地状态', value: '已离线可用'),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _Panel(
            title: '新增提醒',
            subtitle: '本地规则可用于后续系统通知接入',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ReminderChip(
                    label: '称重提醒', onTap: () => _addReminder('weight')),
                _ReminderChip(label: '饮食提醒', onTap: () => _addReminder('meal')),
                _ReminderChip(
                    label: '运动提醒', onTap: () => _addReminder('exercise')),
                _ReminderChip(
                    label: '用药提醒', onTap: () => _addReminder('medicine')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final recent = _Panel(
                title: '最近打卡',
                subtitle: '饮食、运动、用药、称重',
                child: _RecordList(records: _records),
              );
              final reminderPanel = _Panel(
                title: '提醒规则',
                subtitle: '本地保存的计划提醒',
                child: _ReminderList(
                    reminders: _reminders, onDelete: _repo.deleteReminder),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: recent),
                    const SizedBox(width: 16),
                    Expanded(child: reminderPanel),
                  ],
                );
              }
              return Column(
                children: [
                  recent,
                  const SizedBox(height: 16),
                  reminderPanel,
                ],
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppTheme.deepBlue),
            ),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _ReminderChip extends StatelessWidget {
  const _ReminderChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: AppTheme.pageBg,
      side: const BorderSide(color: AppTheme.cardBorder),
      labelStyle: const TextStyle(
          color: AppTheme.deepBlue, fontWeight: FontWeight.w700),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
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

class _RecordList extends StatelessWidget {
  const _RecordList({required this.records});

  final List<ClockRecordData> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Text('暂无记录。', style: TextStyle(color: AppTheme.muted));
    }
    return Column(
      children: [
        for (final record in records.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.pageBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_iconFor(record.type),
                        color: AppTheme.deepBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${record.label} · ${DateFormat('MM月dd日 HH:mm').format(record.clockTime)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record.note.isEmpty ? '已完成' : record.note,
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                      ],
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

class _ReminderList extends StatelessWidget {
  const _ReminderList({
    required this.reminders,
    required this.onDelete,
  });

  final List<ReminderData> reminders;
  final Future<void> Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return const Text('暂无提醒规则。', style: TextStyle(color: AppTheme.muted));
    }
    return Column(
      children: [
        for (final reminder in reminders.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.pageBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.notifications_active_outlined,
                        color: AppTheme.deepBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${reminder.label} · ${reminder.timeText}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reminder.payload['note'] as String? ?? '本地规则',
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.close),
                    onPressed: reminder.id == null
                        ? null
                        : () async {
                            await onDelete(reminder.id!);
                          },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

IconData _iconFor(String type) {
  return switch (type) {
    'meal' => Icons.restaurant_outlined,
    'exercise' => Icons.directions_run_outlined,
    'medicine' => Icons.medication_outlined,
    'weight' => Icons.scale_outlined,
    _ => Icons.check_circle_outline,
  };
}

String _clockTitle(String type) {
  return switch (type) {
    'meal' => '饮食打卡',
    'exercise' => '运动打卡',
    'medicine' => '用药打卡',
    'weight' => '称重打卡',
    _ => '打卡',
  };
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.type});

  final String type;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('新增$_title'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: '备注'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('提醒时间'),
                subtitle: Text(_time.format(context)),
                trailing: TextButton(
                  onPressed: _pickTime,
                  child: const Text('选择'),
                ),
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
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  String get _title {
    return switch (widget.type) {
      'meal' => '饮食提醒',
      'exercise' => '运动提醒',
      'medicine' => '用药提醒',
      'weight' => '称重提醒',
      _ => '提醒',
    };
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    setState(() => _time = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _ReminderDraft(
        time: TimeOfDayValue(hour: _time.hour, minute: _time.minute),
        note: _noteController.text.trim().isEmpty
            ? _title
            : _noteController.text.trim(),
      ),
    );
  }
}

class _ReminderDraft {
  const _ReminderDraft({required this.time, required this.note});

  final TimeOfDayValue time;
  final String note;
}
