import 'package:flutter/material.dart';

import '../../core/widgets/health_ui.dart';
import '../../core/widgets/numeric_picker_field.dart';
import 'quit_smoking_models.dart';
import 'quit_smoking_repository.dart';

class QuitSmokingCalendarPage extends StatefulWidget {
  const QuitSmokingCalendarPage({
    super.key,
    required this.profile,
    required this.repository,
    required this.events,
  });

  final QuitSmokingProfile profile;
  final QuitSmokingRepository repository;
  final List<QuitSmokingEvent> events;

  @override
  State<QuitSmokingCalendarPage> createState() =>
      _QuitSmokingCalendarPageState();
}

class _QuitSmokingCalendarPageState extends State<QuitSmokingCalendarPage> {
  late List<QuitSmokingEvent> _events;
  late DateTime _focusedMonth;

  @override
  void initState() {
    super.initState();
    _events = widget.events;
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final days = _monthCells(_focusedMonth);
    final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
    final calendarCellHeight =
        58 + ((scaledBodySize - 14).clamp(0, 100) * 5).toDouble();
    final monthEvents = _events.where((event) {
      final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
      return time.year == _focusedMonth.year &&
          time.month == _focusedMonth.month;
    }).toList();
    final recordDays = monthEvents
        .map((event) =>
            _dateOnly(DateTime.fromMillisecondsSinceEpoch(event.occurredAt)))
        .toSet()
        .length;
    final achievedDays = monthEvents
        .where((event) =>
            event.type == QuitSmokingEventType.checkIn && event.success == true)
        .map((event) =>
            _dateOnly(DateTime.fromMillisecondsSinceEpoch(event.occurredAt)))
        .toSet()
        .length;
    final smokedCount = monthEvents
        .where((event) => event.type == QuitSmokingEventType.smoked)
        .fold<int>(0, (sum, event) => sum + event.cigarettes);

    return Scaffold(
      appBar: AppBar(title: const Text('戒烟日历')),
      body: HealthResponsiveContent(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: '上个月',
                          onPressed: () => _changeMonth(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Text(
                            '${_focusedMonth.year} 年 ${_focusedMonth.month} 月',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: '下个月',
                          onPressed: _canGoNext ? () => _changeMonth(1) : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                          Expanded(
                            child: Text(label, textAlign: TextAlign.center),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisExtent: calendarCellHeight,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: days.length,
                      itemBuilder: (context, index) {
                        final day = days[index];
                        final dayEvents = day == null
                            ? const <QuitSmokingEvent>[]
                            : _eventsForDay(day);
                        return day == null
                            ? const SizedBox.shrink()
                            : _CalendarDay(
                                day: day,
                                events: dayEvents,
                                target: quitSmokingTargetForDay(
                                  profile: widget.profile,
                                  events: dayEvents,
                                  day: day,
                                ),
                                enabled:
                                    !day.isAfter(_dateOnly(DateTime.now())) &&
                                        (!day.isBefore(_planStart) ||
                                            dayEvents.isNotEmpty),
                                onTap: () => _openDay(day),
                              );
                      },
                    ),
                    const SizedBox(height: 12),
                    const Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _Legend(
                          icon: Icons.check_circle,
                          color: Colors.teal,
                          label: '已达标',
                        ),
                        _Legend(
                          icon: Icons.error,
                          color: Colors.orange,
                          label: '未达标',
                        ),
                        _Legend(
                          icon: Icons.description,
                          color: Colors.blueGrey,
                          label: '有记录',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                      child: _CalendarMetric(
                        label: '记录天数',
                        value: '$recordDays 天',
                      ),
                    ),
                    Expanded(
                      child: _CalendarMetric(
                        label: '吸烟总数',
                        value: '$smokedCount 支',
                      ),
                    ),
                    Expanded(
                      child: _CalendarMetric(
                        label: '达标天数',
                        value: '$achievedDays 天',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime get _planStart {
    final milliseconds = widget.profile.planStartDate > 0
        ? widget.profile.planStartDate
        : widget.profile.stageStartDate > 0
            ? widget.profile.stageStartDate
            : widget.profile.targetDate;
    return _dateOnly(DateTime.fromMillisecondsSinceEpoch(milliseconds));
  }

  bool get _canGoNext {
    final now = DateTime.now();
    return _focusedMonth.year < now.year ||
        (_focusedMonth.year == now.year && _focusedMonth.month < now.month);
  }

  void _changeMonth(int amount) {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month + amount);
    });
  }

  List<QuitSmokingEvent> _eventsForDay(DateTime day) => _events
      .where((event) => _isSameDay(
          DateTime.fromMillisecondsSinceEpoch(event.occurredAt), day))
      .toList();

  Future<void> _openDay(DateTime day) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuitSmokingDayDetailPage(
          day: day,
          profile: widget.profile,
          repository: widget.repository,
          events: _eventsForDay(day),
        ),
      ),
    );
    final events = await widget.repository.loadEvents();
    if (!mounted) return;
    setState(() {
      _events = events;
    });
  }
}

class QuitSmokingDayDetailPage extends StatefulWidget {
  const QuitSmokingDayDetailPage({
    super.key,
    required this.day,
    required this.profile,
    required this.repository,
    required this.events,
  });

  final DateTime day;
  final QuitSmokingProfile profile;
  final QuitSmokingRepository repository;
  final List<QuitSmokingEvent> events;

  @override
  State<QuitSmokingDayDetailPage> createState() =>
      _QuitSmokingDayDetailPageState();
}

class _QuitSmokingDayDetailPageState extends State<QuitSmokingDayDetailPage> {
  late List<QuitSmokingEvent> _events;

  @override
  void initState() {
    super.initState();
    _events = [...widget.events]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  }

  @override
  Widget build(BuildContext context) {
    final smoked = _events
        .where((event) => event.type == QuitSmokingEventType.smoked)
        .fold<int>(0, (sum, event) => sum + event.cigarettes);
    final cravings = _events
        .where((event) => event.type == QuitSmokingEventType.craving)
        .toList();
    final successes = cravings.where((event) => event.success == true).length;
    final checkIn = _events
        .where((event) => event.type == QuitSmokingEventType.checkIn)
        .firstOrNull;
    final checked = checkIn != null;
    final target = quitSmokingTargetForDay(
      profile: widget.profile,
      events: _events,
      day: widget.day,
    );
    final achieved = checkIn?.success;
    final avoided = (widget.profile.dailyBaseline - smoked)
        .clamp(0, widget.profile.dailyBaseline);
    final saved = widget.profile.packCigarettes <= 0
        ? 0.0
        : avoided / widget.profile.packCigarettes * widget.profile.packPrice;

    return Scaffold(
      appBar: AppBar(title: Text(_fullDate(widget.day))),
      body: HealthResponsiveContent(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          !checked
                              ? Icons.pending_outlined
                              : achieved == true
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                          color: !checked
                              ? null
                              : achieved == true
                                  ? Colors.teal
                                  : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          !checked
                              ? '当日待总结'
                              : achieved == true
                                  ? '当日已达标'
                                  : '当日未达标',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: _CalendarMetric(
                                label: '吸烟', value: '$smoked 支')),
                        Expanded(
                            child: _CalendarMetric(
                                label: '少吸', value: '$avoided 支')),
                        Expanded(
                            child: _CalendarMetric(
                                label: '预计节省',
                                value: '¥${saved.toStringAsFixed(2)}')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      cravings.isEmpty
                          ? '当天没有烟瘾记录'
                          : '烟瘾 ${cravings.length} 次，成功应对 $successes 次',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text('当日目标：不超过 $target 支'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _addEvent,
                    icon: const Icon(Icons.add),
                    label: const Text('新增记录'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: checked ? null : _addCheckIn,
                    icon: const Icon(Icons.task_alt_outlined),
                    label: Text(checked ? '已打卡' : '补充打卡'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
                    child: Text('当日记录',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (_events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 8, 18, 20),
                      child: Text('还没有记录，可以补充当天的实际情况。'),
                    ),
                  for (final event in _events)
                    ListTile(
                      leading: Icon(_eventIcon(event.type)),
                      title: Text(_eventTitle(event)),
                      subtitle: Text(_eventSubtitle(event)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _editEvent(event),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addEvent() async {
    final changed = await showQuitSmokingEventEditor(
      context: context,
      repository: widget.repository,
      day: widget.day,
      hasCheckIn:
          _events.any((event) => event.type == QuitSmokingEventType.checkIn),
    );
    if (changed) await _reload();
  }

  Future<void> _editEvent(QuitSmokingEvent event) async {
    final changed = await showQuitSmokingEventEditor(
      context: context,
      repository: widget.repository,
      day: widget.day,
      event: event,
      hasCheckIn: _events.any((item) =>
          item.type == QuitSmokingEventType.checkIn && item.id != event.id),
    );
    if (changed) await _reload();
  }

  Future<void> _addCheckIn() async {
    final time = widget.day.isAtSameMomentAs(_dateOnly(DateTime.now()))
        ? DateTime.now()
        : DateTime(widget.day.year, widget.day.month, widget.day.day, 20);
    final target = quitSmokingTargetForDay(
      profile: widget.profile,
      events: _events,
      day: widget.day,
    );
    final smoked = _events
        .where((event) => event.type == QuitSmokingEventType.smoked)
        .fold<int>(0, (sum, event) => sum + event.cigarettes);
    await widget.repository.addEvent(
      type: QuitSmokingEventType.checkIn,
      occurredAt: time,
      cigarettes: target,
      intensity: 0,
      success: smoked <= target,
      trigger: '',
      strategy: '',
      note: '',
    );
    await _reload();
  }

  Future<void> _reload() async {
    final all = await widget.repository.loadEvents();
    var dayEvents = all
        .where((event) => _isSameDay(
            DateTime.fromMillisecondsSinceEpoch(event.occurredAt), widget.day))
        .toList();
    final checkIn = dayEvents
        .where((event) => event.type == QuitSmokingEventType.checkIn)
        .firstOrNull;
    if (checkIn != null) {
      final target = checkIn.cigarettes;
      final smoked = dayEvents
          .where((event) => event.type == QuitSmokingEventType.smoked)
          .fold<int>(0, (sum, event) => sum + event.cigarettes);
      final success = smoked <= target;
      if (checkIn.success != success || checkIn.cigarettes != target) {
        final updated = checkIn.copyWith(cigarettes: target, success: success);
        await widget.repository.updateEvent(updated);
        dayEvents = [
          for (final event in dayEvents)
            if (event.id == checkIn.id) updated else event,
        ];
      }
    }
    if (!mounted) return;
    setState(() {
      _events = dayEvents..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    });
  }
}

class QuitSmokingTrendPage extends StatefulWidget {
  const QuitSmokingTrendPage({
    super.key,
    required this.profile,
    required this.events,
  });

  final QuitSmokingProfile profile;
  final List<QuitSmokingEvent> events;

  @override
  State<QuitSmokingTrendPage> createState() => _QuitSmokingTrendPageState();
}

class _QuitSmokingTrendPageState extends State<QuitSmokingTrendPage> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final dates = List.generate(
      _days,
      (index) => today.subtract(Duration(days: _days - index - 1)),
    );
    final counts = dates.map(_smokedCount).toList();
    final total = counts.fold<int>(0, (sum, value) => sum + value);
    final cravings = widget.events.where((event) {
      if (event.type != QuitSmokingEventType.craving) return false;
      return event.occurredAt >= dates.first.millisecondsSinceEpoch;
    }).toList();
    final success = cravings.where((event) => event.success == true).length;
    final checkIns = dates
        .where((day) => widget.events.any((event) =>
            event.type == QuitSmokingEventType.checkIn &&
            _isSameDay(
                DateTime.fromMillisecondsSinceEpoch(event.occurredAt), day)))
        .length;
    final maxValue = [widget.profile.dailyBaseline, ...counts]
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, 1000000);

    return Scaffold(
      appBar: AppBar(title: const Text('戒烟趋势')),
      body: HealthResponsiveContent(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('近 7 天')),
                ButtonSegment(value: 30, label: Text('近 30 天')),
              ],
              selected: {_days},
              onSelectionChanged: (value) =>
                  setState(() => _days = value.first),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('每日吸烟支数',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('柱状高度按每日基线 ${widget.profile.dailyBaseline} 支缩放',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 220,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var index = 0; index < dates.length; index++)
                            Expanded(
                              child: _TrendBar(
                                day: dates[index],
                                count: counts[index],
                                maxValue: maxValue,
                                compact: _days == 30,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('阶段统计',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: _CalendarMetric(
                                label: '累计记录', value: '$total 支')),
                        Expanded(
                            child: _CalendarMetric(
                                label: '打卡率',
                                value: '${(checkIns / _days * 100).round()}%')),
                        Expanded(
                            child: _CalendarMetric(
                                label: '烟瘾应对率',
                                value: cravings.isEmpty
                                    ? '--'
                                    : '${(success / cravings.length * 100).round()}%')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _smokedCount(DateTime day) => widget.events.where((event) {
        return event.type == QuitSmokingEventType.smoked &&
            _isSameDay(
                DateTime.fromMillisecondsSinceEpoch(event.occurredAt), day);
      }).fold<int>(0, (sum, event) => sum + event.cigarettes);
}

Future<bool> showQuitSmokingEventEditor({
  required BuildContext context,
  required QuitSmokingRepository repository,
  required DateTime day,
  QuitSmokingEvent? event,
  bool hasCheckIn = false,
}) async {
  final result = await showDialog<_EventEditResult>(
    context: context,
    builder: (_) => _EventEditorDialog(
      day: day,
      event: event,
      hasCheckIn: hasCheckIn,
    ),
  );
  if (result == null) return false;
  if (result.delete) {
    await repository.deleteEvent(event!);
    if (event.type == QuitSmokingEventType.smoked) {
      await repository.invalidateCheckInForDay(day);
    }
    return true;
  }
  if (event == null) {
    await repository.addEvent(
      type: result.type,
      occurredAt: result.occurredAt,
      cigarettes: result.cigarettes,
      intensity: result.intensity,
      success: result.success,
      trigger: result.trigger,
      strategy: result.strategy,
      note: result.note,
    );
    if (result.type == QuitSmokingEventType.smoked) {
      await repository.invalidateCheckInForDay(day);
    }
  } else {
    await repository.updateEvent(QuitSmokingEvent(
      id: event.id,
      type: event.type,
      occurredAt: result.occurredAt!.millisecondsSinceEpoch,
      cigarettes: result.cigarettes,
      intensity: result.intensity,
      success: result.success,
      trigger: result.trigger,
      strategy: result.strategy,
      note: result.note,
      createdAt: event.createdAt,
    ));
    if (event.type == QuitSmokingEventType.smoked) {
      await repository.invalidateCheckInForDay(day);
    }
  }
  return true;
}

class _EventEditorDialog extends StatefulWidget {
  const _EventEditorDialog({
    required this.day,
    required this.event,
    required this.hasCheckIn,
  });

  final DateTime day;
  final QuitSmokingEvent? event;
  final bool hasCheckIn;

  @override
  State<_EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<_EventEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cigarettes;
  late final TextEditingController _trigger;
  late final TextEditingController _strategy;
  late final TextEditingController _note;
  late QuitSmokingEventType _type;
  late TimeOfDay _time;
  late double _intensity;
  bool _success = true;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final occurredAt = event == null
        ? (widget.day.isAtSameMomentAs(_dateOnly(DateTime.now()))
            ? DateTime.now()
            : DateTime(widget.day.year, widget.day.month, widget.day.day, 20))
        : DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
    _type = event?.type ?? QuitSmokingEventType.smoked;
    _time = TimeOfDay.fromDateTime(occurredAt);
    _intensity = (event?.intensity ?? 3).clamp(1, 5).toDouble();
    _success = event?.success ?? true;
    _cigarettes = TextEditingController(text: '${event?.cigarettes ?? 1}');
    _trigger = TextEditingController(text: event?.trigger ?? '');
    _strategy = TextEditingController(text: event?.strategy ?? '');
    _note = TextEditingController(text: event?.note ?? '');
  }

  @override
  void dispose() {
    _cigarettes.dispose();
    _trigger.dispose();
    _strategy.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.event != null;
    return AlertDialog(
      title: Text(editing ? '记录详情' : '新增记录'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!editing)
                SegmentedButton<QuitSmokingEventType>(
                  segments: [
                    const ButtonSegment(
                        value: QuitSmokingEventType.smoked, label: Text('吸烟')),
                    const ButtonSegment(
                        value: QuitSmokingEventType.craving, label: Text('烟瘾')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) =>
                      setState(() => _type = value.first),
                ),
              if (!editing) const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('发生时间'),
                subtitle:
                    Text('${_fullDate(widget.day)}  ${_time.format(context)}'),
                trailing: const Icon(Icons.schedule_outlined),
                onTap: _pickTime,
              ),
              if (_type == QuitSmokingEventType.smoked) ...[
                NumericPickerField(
                  controller: _cigarettes,
                  label: '吸烟支数',
                  unit: '支',
                  min: 1,
                  max: 100,
                  step: 1,
                  initialValue: 1,
                  validator: (value) {
                    final count = int.tryParse(value?.trim() ?? '');
                    return count == null || count < 1 || count > 100
                        ? '请输入 1 至 100 支'
                        : null;
                  },
                ),
              ],
              if (_type == QuitSmokingEventType.craving) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('烟瘾强度 ${_intensity.round()} / 5'),
                ),
                Slider(
                  value: _intensity,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '${_intensity.round()}',
                  onChanged: (value) => setState(() => _intensity = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('成功应对'),
                  value: _success,
                  onChanged: (value) => setState(() => _success = value),
                ),
              ],
              if (_type != QuitSmokingEventType.checkIn)
                TextField(
                  controller: _trigger,
                  decoration: const InputDecoration(labelText: '诱因（可选）'),
                ),
              if (_type == QuitSmokingEventType.craving)
                TextField(
                  controller: _strategy,
                  decoration: const InputDecoration(labelText: '应对方式（可选）'),
                ),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '备注（可选）'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            onPressed: _confirmDelete,
            child: Text('删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _EventEditResult(
        type: _type,
        occurredAt: DateTime(widget.day.year, widget.day.month, widget.day.day,
            _time.hour, _time.minute),
        cigarettes: _type == QuitSmokingEventType.smoked
            ? int.parse(_cigarettes.text.trim())
            : _type == QuitSmokingEventType.checkIn
                ? (widget.event?.cigarettes ?? 0)
                : 0,
        intensity:
            _type == QuitSmokingEventType.craving ? _intensity.round() : 0,
        success: _type == QuitSmokingEventType.craving
            ? _success
            : _type == QuitSmokingEventType.checkIn
                ? _success
                : null,
        trigger: _trigger.text.trim(),
        strategy: _strategy.text.trim(),
        note: _note.text.trim(),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('删除后，日历和统计会同步更新。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, const _EventEditResult.delete());
    }
  }
}

class _EventEditResult {
  const _EventEditResult({
    required this.type,
    required this.occurredAt,
    required this.cigarettes,
    required this.intensity,
    required this.success,
    required this.trigger,
    required this.strategy,
    required this.note,
  }) : delete = false;

  const _EventEditResult.delete()
      : delete = true,
        type = QuitSmokingEventType.smoked,
        occurredAt = null,
        cigarettes = 0,
        intensity = 0,
        success = null,
        trigger = '',
        strategy = '',
        note = '';

  final bool delete;
  final QuitSmokingEventType type;
  final DateTime? occurredAt;
  final int cigarettes;
  final int intensity;
  final bool? success;
  final String trigger;
  final String strategy;
  final String note;
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.events,
    required this.target,
    required this.enabled,
    required this.onTap,
  });

  final DateTime day;
  final List<QuitSmokingEvent> events;
  final int target;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final checkIn = events
        .where((event) => event.type == QuitSmokingEventType.checkIn)
        .firstOrNull;
    final checked = checkIn != null;
    final smoked = events
        .where((event) => event.type == QuitSmokingEventType.smoked)
        .fold<int>(0, (sum, event) => sum + event.cigarettes);
    final achieved = checkIn?.success ?? smoked <= target;
    final color = checked
        ? (achieved ? Colors.teal : Colors.orange)
        : events.isNotEmpty
            ? Colors.blueGrey
            : Theme.of(context).colorScheme.primary;
    final icon = checked
        ? (achieved ? Icons.check_circle : Icons.error)
        : events.isNotEmpty
            ? Icons.description
            : null;
    final status = checked
        ? (achieved ? '已达标' : '未达标')
        : events.isNotEmpty
            ? '有记录，共吸烟 $smoked 支'
            : '无记录';
    final today = _isSameDay(day, DateTime.now());
    return Semantics(
      label: '${_fullDate(day)}，${enabled ? status : '不可选择'}',
      button: enabled,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Opacity(
            opacity: enabled ? 1 : .38,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: today
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${day.day}'),
                  const SizedBox(height: 3),
                  if (enabled && icon != null)
                    Icon(icon, size: 17, color: color)
                  else
                    const SizedBox(height: 17),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.day,
    required this.count,
    required this.maxValue,
    required this.compact,
  });

  final DateTime day;
  final int count;
  final int maxValue;
  final bool compact;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '${_fullDate(day)}：$count 支',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!compact)
                Text('$count', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: count == 0 ? 3 : 150 * count / maxValue,
                decoration: BoxDecoration(
                  color: count == 0
                      ? Theme.of(context).colorScheme.outlineVariant
                      : Theme.of(context).colorScheme.primary,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ),
              const SizedBox(height: 6),
              if (!compact || day.day == 1 || day.weekday == DateTime.monday)
                Text('${day.month}/${day.day}',
                    maxLines: 1, style: Theme.of(context).textTheme.labelSmall)
              else
                const SizedBox(height: 16),
            ],
          ),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _CalendarMetric extends StatelessWidget {
  const _CalendarMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      );
}

List<DateTime?> _monthCells(DateTime month) {
  final first = DateTime(month.year, month.month);
  final count = DateTime(month.year, month.month + 1, 0).day;
  return [
    ...List<DateTime?>.filled(first.weekday - 1, null),
    ...List.generate(
        count, (index) => DateTime(month.year, month.month, index + 1)),
  ];
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _fullDate(DateTime value) =>
    '${value.year} 年 ${value.month} 月 ${value.day} 日';

IconData _eventIcon(QuitSmokingEventType type) => switch (type) {
      QuitSmokingEventType.smoked => Icons.smoke_free,
      QuitSmokingEventType.craving => Icons.self_improvement_outlined,
      QuitSmokingEventType.checkIn => Icons.task_alt_outlined,
    };

String _eventTitle(QuitSmokingEvent event) => switch (event.type) {
      QuitSmokingEventType.smoked => '吸烟 ${event.cigarettes} 支',
      QuitSmokingEventType.craving =>
        event.success == true ? '成功应对烟瘾' : '未能应对烟瘾',
      QuitSmokingEventType.checkIn =>
        event.success == true ? '戒烟打卡已达标' : '戒烟打卡未达标',
    };

String _eventSubtitle(QuitSmokingEvent event) {
  final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
  final parts = <String>[
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    if (event.intensity > 0) '强度 ${event.intensity}/5',
    if (event.trigger.isNotEmpty) event.trigger,
    if (event.strategy.isNotEmpty) event.strategy,
    if (event.note.isNotEmpty) event.note,
  ];
  return parts.join(' · ');
}
