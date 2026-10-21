import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class RoutineGoalDialog extends StatefulWidget {
  const RoutineGoalDialog({super.key, required this.settings});
  final Map<String, dynamic> settings;

  @override
  State<RoutineGoalDialog> createState() => _RoutineGoalDialogState();
}

class _RoutineGoalDialogState extends State<RoutineGoalDialog> {
  late String? wake = widget.settings['wakeTarget'];
  late String? bed = widget.settings['bedTarget'];
  late num? rest = widget.settings['restTargetHours'];
  late String wakeMode = widget.settings['wakeReminderMode'] ??
      (widget.settings['wakeReminder'] == true ? 'app' : 'none');
  late int bedLead = widget.settings['bedReminder'] == true
      ? (widget.settings['bedReminderLeadMinutes'] as num?)?.toInt() ?? 0
      : -1;
  late Set<int> wakeDays = Set<int>.from(
      widget.settings['wakeReminderDays'] ?? [1, 2, 3, 4, 5, 6, 7]);
  late Set<int> bedDays = Set<int>.from(
      widget.settings['bedReminderDays'] ?? [1, 2, 3, 4, 5, 6, 7]);
  late String wakeRepeat = repeatPreset(wakeDays);
  late String bedRepeat = repeatPreset(bedDays);

  String repeatPreset(Set<int> days) => days.length == 7
      ? 'daily'
      : days.length == 5 && days.every((day) => day <= 5)
          ? 'workdays'
          : 'custom';

  Widget choiceField<T>({
    required String title,
    required T value,
    required Map<T, String> options,
    required ValueChanged<T>? onChanged,
  }) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(options[value]!),
        trailing: const Icon(Icons.chevron_right),
        enabled: onChanged != null,
        onTap: onChanged == null
            ? null
            : () async {
                final selected = await showModalBottomSheet<T>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (context) => SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                          child: Text(title,
                              style: Theme.of(context).textTheme.titleLarge),
                        ),
                        for (final option in options.entries)
                          ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            title: Text(option.value),
                            selected: option.key == value,
                            trailing: Icon(option.key == value
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked),
                            onTap: () => Navigator.pop(context, option.key),
                          ),
                      ]),
                    ),
                  ),
                );
                if (selected != null && mounted) onChanged(selected);
              },
      );

  Widget repeatDays(String field) {
    final days = field == 'wake' ? wakeDays : bedDays;
    void update(Set<int> value) => setState(() {
          if (field == 'wake') {
            wakeDays = value;
          } else {
            bedDays = value;
          }
        });
    final preset = field == 'wake' ? wakeRepeat : bedRepeat;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      choiceField<String>(
        title: '重复日期',
        value: preset,
        options: const {'daily': '每天', 'workdays': '工作日', 'custom': '自选星期'},
        onChanged: (value) {
          setState(() {
            if (field == 'wake') {
              wakeRepeat = value;
            } else {
              bedRepeat = value;
            }
          });
          if (value != 'custom') {
            update(value == 'daily' ? {1, 2, 3, 4, 5, 6, 7} : {1, 2, 3, 4, 5});
          }
        },
      ),
      if (preset == 'custom')
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 6, children: [
            for (var day = 1; day <= 7; day++)
              FilterChip(
                label:
                    Text(['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day - 1]),
                selected: days.contains(day),
                onSelected: (selected) {
                  final next = {...days};
                  if (selected) {
                    next.add(day);
                  } else if (next.length > 1) {
                    next.remove(day);
                  }
                  update(next);
                },
              ),
          ]),
        ),
    ]);
  }

  Widget reminderOptions(String field) {
    final isWake = field == 'wake';
    final hasTime = (isWake ? wake : bed) != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (isWake)
          choiceField<String>(
            title: '起床提醒',
            value: hasTime ? wakeMode : 'none',
            options: {
              'none': '不提醒',
              'app': 'APP 通知',
              if ((!kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.android) ||
                  wakeMode == 'alarm')
                'alarm': '手机系统闹钟',
            },
            onChanged:
                !hasTime ? null : (value) => setState(() => wakeMode = value),
          )
        else
          choiceField<int>(
            title: '睡前提醒',
            value: hasTime ? bedLead : -1,
            options: const {
              -1: '不提醒',
              0: '准点提醒',
              15: '提前 15 分钟',
              30: '提前 30 分钟'
            },
            onChanged:
                !hasTime ? null : (value) => setState(() => bedLead = value),
          ),
        if (hasTime && (isWake ? wakeMode != 'none' : bedLead >= 0)) ...[
          const SizedBox(height: 12),
          repeatDays(field),
          if (isWake && wakeMode == 'alarm')
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('保存后前往手机时钟确认。以后修改或关闭闹钟，请到手机时钟操作；响铃不会自动打卡。'),
            ),
          if (!isWake)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('重复日期按睡前目标所在日期计算。'),
            ),
        ],
      ]),
    );
  }

  String durationLabel(num hours) {
    final minutes = (hours * 60).round();
    return '${minutes ~/ 60} 小时${minutes % 60 == 0 ? '' : ' ${minutes % 60} 分钟'}';
  }

  Future<void> choose(String field) async {
    final isRest = field == 'rest';
    final title = isRest
        ? '目标休息时长'
        : field == 'wake'
            ? '起床时间'
            : '睡前时间';
    final time = (field == 'wake' ? wake : bed)?.split(':');
    var hour = time == null ? (field == 'wake' ? 7 : 23) : int.parse(time[0]);
    var minute = time == null ? 0 : int.parse(time[1]);
    var quarter = (((rest ?? 8) * 4).round().clamp(4, 64)) - 4;
    final controllers = [
      FixedExtentScrollController(initialItem: isRest ? quarter : hour),
      if (!isRest) FixedExtentScrollController(initialItem: minute),
    ];
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 300,
          height: 220,
          child: Row(children: [
            for (var column = 0; column < controllers.length; column++)
              Expanded(
                child: ListWheelScrollView.useDelegate(
                  controller: controllers[column],
                  itemExtent: (MediaQuery.textScalerOf(context).scale(20) * 2.5)
                      .clamp(52.0, double.infinity),
                  physics: const FixedExtentScrollPhysics(),
                  diameterRatio: 1.6,
                  overAndUnderCenterOpacity: .35,
                  onSelectedItemChanged: (value) {
                    if (isRest) {
                      quarter = value;
                    } else if (column == 0) {
                      hour = value;
                    } else {
                      minute = value;
                    }
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: isRest
                        ? 61
                        : column == 0
                            ? 24
                            : 60,
                    builder: (context, index) => Center(
                      child: Text(
                        isRest
                            ? durationLabel((index + 4) / 4)
                            : '${index.toString().padLeft(2, '0')} ${column == 0 ? '时' : '分'}',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认')),
        ],
      ),
    );
    final accepted = await Navigator.of(context).push(route);
    await route.completed;
    for (final controller in controllers) {
      controller.dispose();
    }
    if (accepted != true || !mounted) return;
    setState(() {
      if (isRest) {
        rest = (quarter + 4) / 4;
      } else {
        final value =
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        if (field == 'wake') {
          wake = value;
        } else {
          bed = value;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('我的作息目标'),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final field in ['wake', 'bed', 'rest']) ...[
                ListTile(
                  title: Text(field == 'wake'
                      ? '起床时间'
                      : field == 'bed'
                          ? '睡前时间'
                          : '目标休息时长'),
                  subtitle: Text(field == 'wake'
                      ? wake ?? '未设置'
                      : field == 'bed'
                          ? bed ?? '未设置'
                          : rest == null
                              ? '未设置'
                              : durationLabel(rest!)),
                  onTap: () => choose(field),
                  trailing: (field == 'wake'
                              ? wake
                              : field == 'bed'
                                  ? bed
                                  : rest) ==
                          null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          tooltip:
                              '清除${field == 'wake' ? '起床时间' : field == 'bed' ? '睡前时间' : '目标休息时长'}',
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() {
                            if (field == 'wake') {
                              wake = null;
                            } else if (field == 'bed') {
                              bed = null;
                            } else {
                              rest = null;
                            }
                          }),
                        ),
                ),
                if (field != 'rest') reminderOptions(field),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text('时间按北京时间记录。\n休息目标：1—16 小时，每档 15 分钟。'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, <String, dynamic>{
              ...widget.settings,
              'wakeTarget': wake,
              'bedTarget': bed,
              'restTargetHours': rest,
              'wakeReminder': wakeMode == 'app' && wake != null,
              'wakeReminderMode': wake == null ? 'none' : wakeMode,
              'bedReminder': bedLead >= 0 && bed != null,
              'bedReminderLeadMinutes': bedLead < 0 ? 0 : bedLead,
              'wakeReminderDays': wakeDays.toList()..sort(),
              'bedReminderDays': bedDays.toList()..sort(),
            }),
            child: Text(wakeMode == 'alarm' && wake != null ? '保存并设置闹钟' : '保存'),
          ),
        ],
      );
}
