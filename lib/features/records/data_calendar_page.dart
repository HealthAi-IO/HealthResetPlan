import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';

class DataCalendarPage extends StatefulWidget {
  const DataCalendarPage({super.key});

  @override
  State<DataCalendarPage> createState() => _DataCalendarPageState();
}

class _DataCalendarPageState extends State<DataCalendarPage> {
  final _repo = sl<HealthRepository>();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  String _type = 'weight';
  bool _loading = true;
  List<ClockRecordData> _records = const [];
  List<HealthIndicatorEntry> _weights = const [];
  List<MealRecordData> _meals = const [];

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final start = DateTime(_month.year, _month.month, 1);
    final end = DateTime(_month.year, _month.month + 1, 1);
    final results = await Future.wait<Object?>([
      _repo.loadClockRecords(limit: 500),
      _repo.loadIndicators(type: 'weight', limit: 500),
      _repo.loadMealsBetween(start, end),
    ]);
    if (!mounted) return;
    setState(() {
      _records = results[0] as List<ClockRecordData>;
      _weights = results[1] as List<HealthIndicatorEntry>;
      _meals = results[2] as List<MealRecordData>;
      _loading = false;
    });
  }

  void _changeMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      _selectedDate = DateTime(_month.year, _month.month, 1);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final colors = Theme.of(context).colorScheme;
    final first = DateTime(_month.year, _month.month, 1);
    final leading = first.weekday % 7;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    return ListView(
      key: const PageStorageKey('data-calendar'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        Row(children: [
          const Expanded(
            child: Text('数据日历',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: '上个月',
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(DateFormat('yyyy年M月', 'zh_CN').format(_month),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(
            tooltip: '下个月',
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'weight', label: Text('体重')),
            ButtonSegment(value: 'water', label: Text('饮水')),
            ButtonSegment(value: 'exercise', label: Text('运动')),
            ButtonSegment(value: 'meal', label: Text('饮食')),
          ],
          selected: {_type},
          onSelectionChanged: (value) => setState(() => _type = value.first),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(children: [
            Row(
              children: [
                for (final label in ['日', '一', '二', '三', '四', '五', '六'])
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant)),
                    ),
                  ),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leading + days,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 44,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemBuilder: (_, index) {
                if (index < leading) return const SizedBox.shrink();
                final day =
                    DateTime(_month.year, _month.month, index - leading + 1);
                final selected = DateUtils.isSameDay(day, _selectedDate);
                final isToday = DateUtils.isSameDay(day, DateTime.now());
                final value = _valueForDay(day);
                return InkWell(
                  onTap: () => setState(() => _selectedDate = day),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primary
                          : value.isEmpty
                              ? Colors.transparent
                              : colors.primaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? colors.primary
                            : isToday
                                ? colors.primary
                                : Colors.transparent,
                      ),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              color: selected
                                  ? colors.onPrimary
                                  : value.isEmpty
                                      ? colors.onSurface
                                      : colors.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (value.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: selected
                                    ? colors.onPrimary
                                    : colors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ]),
                  ),
                );
              },
            ),
          ]),
        ),
        const SizedBox(height: 14),
        _DayDetails(
          date: _selectedDate,
          type: _type,
          records: _records,
          weights: _weights,
          meals: _meals,
        ),
      ],
    );
  }

  String _valueForDay(DateTime day) {
    if (_type == 'weight') {
      final entries =
          _weights.where((item) => DateUtils.isSameDay(item.measuredTime, day));
      final value = entries.firstOrNull?.numericTrendValue;
      return value == null ? '' : '${value.toStringAsFixed(1)}kg';
    }
    if (_type == 'meal') {
      final meals =
          _meals.where((item) => DateUtils.isSameDay(item.eatenTime, day));
      if (meals.isEmpty) return '';
      final calories =
          meals.fold<double>(0, (sum, item) => sum + item.totalCalories);
      return '${meals.length}餐\n${calories.toStringAsFixed(0)}kcal';
    }
    final count = _records
        .where((item) =>
            item.type == _type && DateUtils.isSameDay(item.clockTime, day))
        .length;
    return count == 0 ? '' : '$count次';
  }
}

class _DayDetails extends StatelessWidget {
  const _DayDetails({
    required this.date,
    required this.type,
    required this.records,
    required this.weights,
    required this.meals,
  });

  final DateTime date;
  final String type;
  final List<ClockRecordData> records;
  final List<HealthIndicatorEntry> weights;
  final List<MealRecordData> meals;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[];
    if (type == 'weight') {
      for (final item in weights
          .where((item) => DateUtils.isSameDay(item.measuredTime, date))) {
        items.add(
            (DateFormat('HH:mm').format(item.measuredTime), item.displayValue));
      }
    } else if (type == 'meal') {
      for (final item
          in meals.where((item) => DateUtils.isSameDay(item.eatenTime, date))) {
        items.add((
          DateFormat('HH:mm').format(item.eatenTime),
          '${item.mealLabel} ${item.name} · ${item.totalCalories.toStringAsFixed(0)} kcal'
        ));
      }
    } else {
      for (final item in records.where((item) =>
          item.type == type && DateUtils.isSameDay(item.clockTime, date))) {
        items.add((
          DateFormat('HH:mm').format(item.clockTime),
          item.note.isEmpty ? item.label : item.note
        ));
      }
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(DateFormat('M月d日', 'zh_CN').format(date),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                '当天暂无记录',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final item in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 48,
                child: Text(item.$1,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              title: Text(item.$2),
            ),
      ]),
    );
  }
}
