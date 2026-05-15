import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _birthYearController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _medicalHistoryController = TextEditingController();
  final _medicationsController = TextEditingController();

  String _gender = 'female';
  bool _loading = true;
  bool _saving = false;
  UserProfileData? _profile;
  List<HealthIndicatorEntry> _indicators = const [];

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _nicknameController.dispose();
    _birthYearController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _medicalHistoryController.dispose();
    _medicationsController.dispose();
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
    final profile = await _repo.loadProfile();
    final indicators = await _repo.loadIndicators(limit: 10);
    if (!mounted) return;
    _profile = profile;
    _indicators = indicators;
    _syncControllers(profile);
    setState(() => _loading = false);
  }

  void _syncControllers(UserProfileData? profile) {
    if (profile == null) return;
    _nicknameController.text = profile.nickname;
    _birthYearController.text =
        profile.birthYear == 0 ? '' : profile.birthYear.toString();
    _heightController.text =
        profile.heightCm == 0 ? '' : profile.heightCm.toStringAsFixed(1);
    _weightController.text =
        profile.weightKg == 0 ? '' : profile.weightKg.toStringAsFixed(1);
    _medicalHistoryController.text = profile.medicalHistory;
    _medicationsController.text = profile.medications;
    _gender = profile.gender.isEmpty ? 'female' : profile.gender;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _repo.saveProfile(
      UserProfileData(
        id: _profile?.id,
        userId: kLocalUserId,
        nickname: _nicknameController.text.trim(),
        gender: _gender,
        birthYear: int.parse(_birthYearController.text.trim()),
        heightCm: double.parse(_heightController.text.trim()),
        weightKg: double.parse(_weightController.text.trim()),
        medicalHistory: _medicalHistoryController.text.trim(),
        medications: _medicationsController.text.trim(),
        createdAt: _profile?.createdAt ?? now,
        updatedAt: now,
        version: _profile?.version ?? 0,
        isDirty: 1,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(const SnackBar(content: Text('健康档案已保存到本地')));
  }

  Future<void> _addIndicatorDialog(String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_IndicatorDraft>(
      context: context,
      builder: (_) => _IndicatorDialog(type: type),
    );
    if (result == null) return;
    await _repo.addIndicator(
      type: type,
      payload: result.payload,
      source: result.source,
      measuredAt: result.measuredAt,
    );
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('已保存健康指标')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final profile = _profile ?? UserProfileData.empty();
    final bottomPadding =
        MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
        children: [
          _OverviewCard(profile: profile, indicators: _indicators),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final form = Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nicknameController,
                      decoration: const InputDecoration(labelText: '昵称'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? '请输入昵称'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _gender,
                      decoration: const InputDecoration(labelText: '性别'),
                      items: const [
                        DropdownMenuItem(value: 'female', child: Text('女')),
                        DropdownMenuItem(value: 'male', child: Text('男')),
                        DropdownMenuItem(value: 'unknown', child: Text('未填写')),
                      ],
                      onChanged: (value) =>
                          setState(() => _gender = value ?? 'unknown'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _birthYearController,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '出生年份'),
                            validator: (value) {
                              final year = int.tryParse(value?.trim() ?? '');
                              if (year == null ||
                                  year < 1900 ||
                                  year > DateTime.now().year) {
                                return '请输入正确年份';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _heightController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: '身高（cm）'),
                            validator: (value) {
                              final height =
                                  double.tryParse(value?.trim() ?? '');
                              if (height == null || height <= 0) return '请输入身高';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _weightController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '体重（kg）'),
                      validator: (value) {
                        final weight = double.tryParse(value?.trim() ?? '');
                        if (weight == null || weight <= 0) return '请输入体重';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _medicalHistoryController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '既往病史'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _medicationsController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '用药记录'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveProfile,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('保存档案'),
                    ),
                  ],
                ),
              );

              final quickActions = _Panel(
                title: '快速记录',
                subtitle: '本地录入最近指标',
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _QuickActionChip(
                      icon: Icons.favorite_outline,
                      label: '血压',
                      onTap: () => _addIndicatorDialog('bp'),
                    ),
                    _QuickActionChip(
                      icon: Icons.scale_outlined,
                      label: '体重',
                      onTap: () => _addIndicatorDialog('weight'),
                    ),
                    _QuickActionChip(
                      icon: Icons.monitor_heart_outlined,
                      label: '血糖',
                      onTap: () => _addIndicatorDialog('glucose'),
                    ),
                    _QuickActionChip(
                      icon: Icons.science_outlined,
                      label: '血脂',
                      onTap: () => _addIndicatorDialog('lipid'),
                    ),
                  ],
                ),
              );

              final recent = _Panel(
                title: '最近指标',
                subtitle: '本地记录会优先用于计划生成',
                child: _IndicatorList(indicators: _indicators),
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: _Panel(
                            title: '基础档案',
                            subtitle: '完善后可用于本地计划计算',
                            child: form)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          quickActions,
                          const SizedBox(height: 16),
                          recent,
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  _Panel(title: '基础档案', subtitle: '完善后可用于本地计划计算', child: form),
                  const SizedBox(height: 16),
                  quickActions,
                  const SizedBox(height: 16),
                  recent,
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

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.profile,
    required this.indicators,
  });

  final UserProfileData profile;
  final List<HealthIndicatorEntry> indicators;

  @override
  Widget build(BuildContext context) {
    HealthIndicatorEntry? latestByType(String type) {
      for (final item in indicators) {
        if (item.type == type) return item;
      }
      return null;
    }

    final latestWeight = latestByType('weight');
    final latestBp = latestByType('bp');
    return _Panel(
      title: '档案概览',
      subtitle: '本地资料与最近记录',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 4 : 2;
          return GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: columns >= 4 ? 1.65 : 1.28,
            children: [
              _SmallMetric(
                  title: '年龄',
                  value: profile.age == 0 ? '--' : '${profile.age}岁'),
              _SmallMetric(
                  title: 'BMI',
                  value:
                      profile.bmi == 0 ? '--' : profile.bmi.toStringAsFixed(1)),
              _SmallMetric(
                  title: '最新体重', value: latestWeight?.displayValue ?? '--'),
              _SmallMetric(
                  title: '最新血压', value: latestBp?.displayValue ?? '--'),
            ],
          );
        },
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(16),
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

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
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
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.pageBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.deepBlue),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
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

class _IndicatorList extends StatelessWidget {
  const _IndicatorList({required this.indicators});

  final List<HealthIndicatorEntry> indicators;

  @override
  Widget build(BuildContext context) {
    if (indicators.isEmpty) {
      return const Text(
        '暂无记录。',
        style: TextStyle(color: AppTheme.muted),
      );
    }
    return Column(
      children: [
        for (final item in indicators.take(6))
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
                    child: Icon(_iconFor(item.type),
                        color: AppTheme.deepBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(item.displayValue,
                            style: const TextStyle(color: AppTheme.muted)),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('MM/dd').format(item.measuredTime),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
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
    'bp' => Icons.favorite_outline,
    'weight' => Icons.scale_outlined,
    'glucose' => Icons.monitor_heart_outlined,
    'lipid' => Icons.science_outlined,
    'heart_rate' => Icons.favorite_border,
    _ => Icons.fiber_manual_record_outlined,
  };
}

class _IndicatorDialog extends StatefulWidget {
  const _IndicatorDialog({required this.type});

  final String type;

  @override
  State<_IndicatorDialog> createState() => _IndicatorDialogState();
}

class _IndicatorDialogState extends State<_IndicatorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  final _weight = TextEditingController();
  final _glucose = TextEditingController();
  final _tc = TextEditingController();
  final _ldl = TextEditingController();
  DateTime _measuredAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.type == 'bp') {
      _systolic.text = '130';
      _diastolic.text = '82';
    } else if (widget.type == 'weight') {
      _weight.text = '74.0';
    } else if (widget.type == 'glucose') {
      _glucose.text = '5.8';
    } else if (widget.type == 'lipid') {
      _tc.text = '5.4';
      _ldl.text = '3.3';
    }
  }

  @override
  void dispose() {
    _systolic.dispose();
    _diastolic.dispose();
    _weight.dispose();
    _glucose.dispose();
    _tc.dispose();
    _ldl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('录入$_title'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.type == 'bp') ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _systolic,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '收缩压'),
                        validator: (value) {
                          if (int.tryParse(value ?? '') == null) return '请输入数值';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _diastolic,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '舒张压'),
                        validator: (value) {
                          if (int.tryParse(value ?? '') == null) return '请输入数值';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ] else if (widget.type == 'weight') ...[
                TextFormField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '体重（kg）'),
                  validator: (value) {
                    if (double.tryParse(value ?? '') == null) return '请输入数值';
                    return null;
                  },
                ),
              ] else if (widget.type == 'glucose') ...[
                TextFormField(
                  controller: _glucose,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '血糖（mmol/L）'),
                  validator: (value) {
                    if (double.tryParse(value ?? '') == null) return '请输入数值';
                    return null;
                  },
                ),
              ] else if (widget.type == 'lipid') ...[
                TextFormField(
                  controller: _tc,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '总胆固醇（mmol/L）'),
                  validator: (value) {
                    if (double.tryParse(value ?? '') == null) return '请输入数值';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ldl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'LDL-C（mmol/L）'),
                  validator: (value) {
                    if (double.tryParse(value ?? '') == null) return '请输入数值';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('测量时间'),
                subtitle:
                    Text(DateFormat('yyyy-MM-dd HH:mm').format(_measuredAt)),
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
      'bp' => '血压',
      'weight' => '体重',
      'glucose' => '血糖',
      'lipid' => '血脂',
      _ => '指标',
    };
  }

  Future<void> _pickTime() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _measuredAt,
    );
    if (picked == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_measuredAt));
    if (time == null) return;
    setState(() {
      _measuredAt = DateTime(
          picked.year, picked.month, picked.day, time.hour, time.minute);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final payload = switch (widget.type) {
      'bp' => {
          'systolic': int.parse(_systolic.text.trim()),
          'diastolic': int.parse(_diastolic.text.trim()),
        },
      'weight' => {'weightKg': double.parse(_weight.text.trim())},
      'glucose' => {'glucoseMmol': double.parse(_glucose.text.trim())},
      'lipid' => {
          'tc': double.parse(_tc.text.trim()),
          'ldl': double.parse(_ldl.text.trim()),
        },
      _ => <String, dynamic>{},
    };
    Navigator.pop(
      context,
      _IndicatorDraft(
        payload: payload,
        source: 'manual',
        measuredAt: _measuredAt,
      ),
    );
  }
}

class _IndicatorDraft {
  const _IndicatorDraft({
    required this.payload,
    required this.source,
    required this.measuredAt,
  });

  final Map<String, dynamic> payload;
  final String source;
  final DateTime measuredAt;
}
