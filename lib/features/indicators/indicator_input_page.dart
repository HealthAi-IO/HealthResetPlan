import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/telemetry_api.dart';

// 录入新指标 / 编辑已有指标
class IndicatorInputPage extends StatefulWidget {
  const IndicatorInputPage({super.key, this.existing, this.defaultType});

  final HealthIndicatorEntry? existing;
  final String? defaultType;

  @override
  State<IndicatorInputPage> createState() => _IndicatorInputPageState();
}

class _IndicatorInputPageState extends State<IndicatorInputPage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final _formKey = GlobalKey<FormState>();

  String _type = 'weight';
  DateTime _measuredAt = DateTime.now();
  bool _saving = false;

  // 各类型字段 controllers
  final _weightCtrl = TextEditingController();
  final _systolicCtrl = TextEditingController();
  final _diastolicCtrl = TextEditingController();
  final _bpmCtrl = TextEditingController();
  final _glucoseCtrl = TextEditingController();
  final _glucoseTypeCtrl = ValueNotifier<String>('fasting');
  final _tcCtrl = TextEditingController();
  final _ldlCtrl = TextEditingController();
  final _hdlCtrl = TextEditingController();
  final _tgCtrl = TextEditingController();
  final _bodyFatCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _spo2Ctrl = TextEditingController();
  final _sleepHoursCtrl = TextEditingController();
  final _sleepQualityCtrl = ValueNotifier<String>('good');
  final _stepsCtrl = TextEditingController();

  static const _typeList = [
    ('weight', '体重', Icons.scale_outlined),
    ('bp', '血压', Icons.favorite_outline),
    ('glucose', '血糖', Icons.water_drop_outlined),
    ('heart_rate', '心率', Icons.monitor_heart_outlined),
    ('lipid', '血脂', Icons.science_outlined),
    ('body_fat', '体脂率', Icons.person_outlined),
    ('waist', '腰围', Icons.straighten_outlined),
    ('spo2', '血氧', Icons.air_outlined),
    ('sleep', '睡眠', Icons.bedtime_outlined),
    ('steps', '步数', Icons.directions_walk_outlined),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.defaultType != null) {
      _type = widget.defaultType!;
    }
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _measuredAt = e.measuredTime;
      _fillFromExisting(e);
    }
  }

  void _fillFromExisting(HealthIndicatorEntry e) {
    switch (e.type) {
      case 'weight':
        _weightCtrl.text = '${e.payload['weightKg'] ?? ''}';
      case 'bp':
        _systolicCtrl.text = '${e.payload['systolic'] ?? ''}';
        _diastolicCtrl.text = '${e.payload['diastolic'] ?? ''}';
        _bpmCtrl.text = '${e.payload['heartRate'] ?? ''}';
      case 'glucose':
        _glucoseCtrl.text = '${e.payload['glucoseMmol'] ?? ''}';
        _glucoseTypeCtrl.value = e.payload['mealType'] as String? ?? 'fasting';
      case 'heart_rate':
        _bpmCtrl.text = '${e.payload['bpm'] ?? ''}';
      case 'lipid':
        _tcCtrl.text = '${e.payload['tc'] ?? ''}';
        _ldlCtrl.text = '${e.payload['ldl'] ?? ''}';
        _hdlCtrl.text = '${e.payload['hdl'] ?? ''}';
        _tgCtrl.text = '${e.payload['tg'] ?? ''}';
      case 'body_fat':
        _bodyFatCtrl.text = '${e.payload['bodyFatPct'] ?? ''}';
      case 'waist':
        _waistCtrl.text = '${e.payload['waistCm'] ?? ''}';
      case 'spo2':
        _spo2Ctrl.text = '${e.payload['spo2Pct'] ?? ''}';
      case 'sleep':
        _sleepHoursCtrl.text = '${e.payload['sleepHours'] ?? ''}';
        _sleepQualityCtrl.value = e.payload['quality'] as String? ?? 'good';
      case 'steps':
        _stepsCtrl.text = '${e.payload['steps'] ?? ''}';
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _systolicCtrl.dispose();
    _diastolicCtrl.dispose();
    _bpmCtrl.dispose();
    _glucoseCtrl.dispose();
    _glucoseTypeCtrl.dispose();
    _tcCtrl.dispose();
    _ldlCtrl.dispose();
    _hdlCtrl.dispose();
    _tgCtrl.dispose();
    _bodyFatCtrl.dispose();
    _waistCtrl.dispose();
    _spo2Ctrl.dispose();
    _sleepHoursCtrl.dispose();
    _sleepQualityCtrl.dispose();
    _stepsCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildPayload() {
    return switch (_type) {
      'weight' => {'weightKg': double.parse(_weightCtrl.text)},
      'bp' => {
          'systolic': int.parse(_systolicCtrl.text),
          'diastolic': int.parse(_diastolicCtrl.text),
          if (_bpmCtrl.text.isNotEmpty) 'heartRate': int.parse(_bpmCtrl.text),
        },
      'glucose' => {
          'glucoseMmol': double.parse(_glucoseCtrl.text),
          'mealType': _glucoseTypeCtrl.value,
        },
      'heart_rate' => {'bpm': int.parse(_bpmCtrl.text)},
      'lipid' => {
          if (_tcCtrl.text.isNotEmpty) 'tc': double.parse(_tcCtrl.text),
          if (_ldlCtrl.text.isNotEmpty) 'ldl': double.parse(_ldlCtrl.text),
          if (_hdlCtrl.text.isNotEmpty) 'hdl': double.parse(_hdlCtrl.text),
          if (_tgCtrl.text.isNotEmpty) 'tg': double.parse(_tgCtrl.text),
        },
      'body_fat' => {'bodyFatPct': double.parse(_bodyFatCtrl.text)},
      'waist'    => {'waistCm': double.parse(_waistCtrl.text)},
      'spo2'     => {'spo2Pct': int.parse(_spo2Ctrl.text)},
      'sleep'    => {
          'sleepHours': double.parse(_sleepHoursCtrl.text),
          'quality': _sleepQualityCtrl.value,
        },
      'steps'    => {'steps': int.parse(_stepsCtrl.text)},
      _ => {},
    };
  }

  void _clearFields() {
    _weightCtrl.clear();
    _systolicCtrl.clear();
    _diastolicCtrl.clear();
    _bpmCtrl.clear();
    _glucoseCtrl.clear();
    _glucoseTypeCtrl.value = 'fasting';
    _tcCtrl.clear();
    _ldlCtrl.clear();
    _hdlCtrl.clear();
    _tgCtrl.clear();
    _bodyFatCtrl.clear();
    _waistCtrl.clear();
    _spo2Ctrl.clear();
    _sleepHoursCtrl.clear();
    _sleepQualityCtrl.value = 'good';
    _stepsCtrl.clear();
    _measuredAt = DateTime.now();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final payload = _buildPayload();
      if (widget.existing?.id != null) {
        await _repo.updateIndicator(widget.existing!.id!, payload);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        await _repo.addIndicator(
          type: _type,
          payload: payload,
          measuredAt: _measuredAt,
        );
        sl<TelemetryApi>().record('indicator_recorded');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已保存，可继续录入下一项'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(_clearFields);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _measuredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_measuredAt),
    );
    if (!mounted) return;
    setState(() {
      _measuredAt = DateTime(
        date.year, date.month, date.day,
        time?.hour ?? _measuredAt.hour,
        time?.minute ?? _measuredAt.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑指标' : '录入健康指标'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!isEdit) ...[
              _SectionLabel('指标类型'),
              const SizedBox(height: 10),
              _TypeSelector(
                value: _type,
                types: _typeList,
                onChanged: (v) => setState(() => _type = v),
              ),
              const SizedBox(height: 20),
            ],
            _SectionLabel('测量时间'),
            const SizedBox(height: 10),
            _DatePickerTile(value: _measuredAt, onTap: _pickDate),
            const SizedBox(height: 20),
            _SectionLabel('数值录入'),
            const SizedBox(height: 10),
            _buildFields(),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isEdit ? '保存修改' : '保存记录', style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildFields() {
    return switch (_type) {
      'weight' => _Card(child: _NumField(
          controller: _weightCtrl,
          label: '体重',
          unit: 'kg',
          hint: '例如 70.5',
          min: 20,
          max: 300,
          decimal: true,
          required: true,
        )),
      'bp' => _Card(
          child: Column(children: [
            _NumField(controller: _systolicCtrl, label: '收缩压（高压）', unit: 'mmHg', hint: '例如 115', min: 60, max: 250, required: true),
            const SizedBox(height: 14),
            _NumField(controller: _diastolicCtrl, label: '舒张压（低压）', unit: 'mmHg', hint: '例如 75', min: 40, max: 160, required: true),
            const SizedBox(height: 14),
            _NumField(controller: _bpmCtrl, label: '同测心率（选填）', unit: 'bpm', hint: '例如 72', min: 30, max: 220),
          ]),
        ),
      'glucose' => _Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _NumField(controller: _glucoseCtrl, label: '血糖', unit: 'mmol/L', hint: '例如 5.0', min: 1, max: 40, decimal: true, required: true),
            const SizedBox(height: 14),
            const Text('测量类型', style: TextStyle(fontSize: 13, color: AppTheme.muted)),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: _glucoseTypeCtrl,
              builder: (_, val, __) => Wrap(
                spacing: 10,
                children: [
                  _TypeChip(label: '空腹', value: 'fasting', selected: val == 'fasting', onTap: (v) => _glucoseTypeCtrl.value = v),
                  _TypeChip(label: '餐后2h', value: 'postmeal', selected: val == 'postmeal', onTap: (v) => _glucoseTypeCtrl.value = v),
                  _TypeChip(label: '随机', value: 'random', selected: val == 'random', onTap: (v) => _glucoseTypeCtrl.value = v),
                ],
              ),
            ),
          ]),
        ),
      'heart_rate' => _Card(child: _NumField(
          controller: _bpmCtrl,
          label: '心率',
          unit: 'bpm',
          hint: '例如 72',
          min: 30,
          max: 220,
          required: true,
        )),
      'lipid' => _Card(
          child: Column(children: [
            _NumField(controller: _tcCtrl, label: '总胆固醇 TC', unit: 'mmol/L', hint: '例如 4.8', min: 1, max: 20, decimal: true),
            const SizedBox(height: 14),
            _NumField(controller: _ldlCtrl, label: 'LDL 低密度脂蛋白', unit: 'mmol/L', hint: '例如 2.8', min: 0.5, max: 15, decimal: true),
            const SizedBox(height: 14),
            _NumField(controller: _hdlCtrl, label: 'HDL 高密度脂蛋白', unit: 'mmol/L', hint: '例如 1.4', min: 0.3, max: 5, decimal: true),
            const SizedBox(height: 14),
            _NumField(controller: _tgCtrl, label: '甘油三酯 TG', unit: 'mmol/L', hint: '例如 1.3', min: 0.2, max: 20, decimal: true),
            const SizedBox(height: 8),
            const Text('血脂各项均为选填，录入已有检查报告结果即可。',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          ]),
        ),
      'body_fat' => _Card(child: _NumField(
          controller: _bodyFatCtrl,
          label: '体脂率',
          unit: '%',
          hint: '例如 25.3',
          min: 3,
          max: 60,
          decimal: true,
          required: true,
        )),
      'waist' => _Card(child: _NumField(
          controller: _waistCtrl,
          label: '腰围',
          unit: 'cm',
          hint: '例如 82.5',
          min: 40,
          max: 200,
          decimal: true,
          required: true,
        )),
      'spo2' => _Card(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NumField(
              controller: _spo2Ctrl,
              label: '血氧饱和度',
              unit: '%',
              hint: '例如 98',
              min: 70,
              max: 100,
              required: true,
            ),
            const SizedBox(height: 8),
            const Text('正常值：95 % 以上；低于 90 % 需就医',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          ],
        )),
      'sleep' => _Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _NumField(
              controller: _sleepHoursCtrl,
              label: '睡眠时长',
              unit: 'h',
              hint: '例如 7.5',
              min: 0,
              max: 24,
              decimal: true,
              required: true,
            ),
            const SizedBox(height: 14),
            const Text('睡眠质量', style: TextStyle(fontSize: 13, color: AppTheme.muted)),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: _sleepQualityCtrl,
              builder: (_, val, __) => Wrap(
                spacing: 10,
                children: [
                  _TypeChip(label: '好', value: 'good', selected: val == 'good',
                      onTap: (v) => _sleepQualityCtrl.value = v),
                  _TypeChip(label: '一般', value: 'fair', selected: val == 'fair',
                      onTap: (v) => _sleepQualityCtrl.value = v),
                  _TypeChip(label: '差', value: 'poor', selected: val == 'poor',
                      onTap: (v) => _sleepQualityCtrl.value = v),
                ],
              ),
            ),
          ]),
        ),
      'steps' => _Card(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NumField(
              controller: _stepsCtrl,
              label: '步数',
              unit: '步',
              hint: '例如 8000',
              min: 0,
              max: 100000,
              required: true,
            ),
            const SizedBox(height: 8),
            const Text('建议每日步数：6000 ~ 10000 步',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          ],
        )),
      _ => const SizedBox.shrink(),
    };
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.muted));
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: child,
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.value, required this.types, required this.onChanged});

  final String value;
  final List<(String, String, IconData)> types;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final t in types)
          GestureDetector(
            onTap: () => onChanged(t.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: value == t.$1 ? AppTheme.deepBlue : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: value == t.$1 ? AppTheme.deepBlue : AppTheme.cardBorder,
                  width: value == t.$1 ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(t.$3, size: 18, color: value == t.$1 ? Colors.white : AppTheme.deepBlue),
                  const SizedBox(width: 6),
                  Text(t.$2,
                      style: TextStyle(
                        color: value == t.$1 ? Colors.white : AppTheme.deepBlue,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({required this.value, required this.onTap});

  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, color: AppTheme.deepBlue, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${value.year}年${value.month.toString().padLeft(2, '0')}月${value.day.toString().padLeft(2, '0')}日  '
                '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.muted),
          ],
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({
    required this.controller,
    required this.label,
    required this.unit,
    required this.hint,
    required this.min,
    required this.max,
    this.decimal = false,
    this.required = false,
  });

  final TextEditingController controller;
  final String label;
  final String unit;
  final String hint;
  final double min;
  final double max;
  final bool decimal;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(decimal ? RegExp(r'[\d.]') : RegExp(r'\d')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: unit,
      ),
      validator: (v) {
        if (required && (v == null || v.isEmpty)) return '$label 不能为空';
        if (v == null || v.isEmpty) return null;
        final num = double.tryParse(v);
        if (num == null) return '请输入有效数字';
        if (num < min || num > max) return '请输入 $min ~ $max 之间的值';
        return null;
      },
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(value),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.deepBlue,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: Colors.white,
      selectedColor: AppTheme.deepBlue,
      side: const BorderSide(color: AppTheme.cardBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}
