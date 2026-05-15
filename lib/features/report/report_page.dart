import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  final _systolicController = TextEditingController(text: '132');
  final _diastolicController = TextEditingController(text: '84');
  final _weightController = TextEditingController(text: '74.2');
  final _glucoseController = TextEditingController(text: '5.7');
  final _tcController = TextEditingController(text: '5.4');
  final _ldlController = TextEditingController(text: '3.3');
  final _summaryController = TextEditingController(
    text: '血压轻度偏高，建议低盐饮食、增加步行并关注体重趋势。',
  );

  Uint8List? _imageBytes;
  String? _imageName;
  DateTime _reportDate = DateTime.now();
  bool _saving = false;
  bool _loading = true;
  List<HealthIndicatorEntry> _recent = const [];

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _systolicController.dispose();
    _diastolicController.dispose();
    _weightController.dispose();
    _glucoseController.dispose();
    _tcController.dispose();
    _ldlController.dispose();
    _summaryController.dispose();
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
    final indicators = await _repo.loadIndicators(limit: 8);
    if (!mounted) return;
    setState(() {
      _recent = indicators;
      _loading = false;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageName = file.name;
    });
  }

  void _fillSample() {
    setState(() {
      _systolicController.text = '132';
      _diastolicController.text = '84';
      _weightController.text = '74.2';
      _glucoseController.text = '5.7';
      _tcController.text = '5.4';
      _ldlController.text = '3.3';
      _summaryController.text = '血压轻度偏高，建议减少盐分摄入并保持规律运动。';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final tasks = <Future<void>>[];
    final measuredAt = _reportDate;

    tasks.add(
      _repo.addIndicator(
        type: 'bp',
        payload: {
          'systolic': int.parse(_systolicController.text.trim()),
          'diastolic': int.parse(_diastolicController.text.trim()),
          'summary': _summaryController.text.trim(),
        },
        source: 'report',
        measuredAt: measuredAt,
      ),
    );
    tasks.add(
      _repo.addIndicator(
        type: 'weight',
        payload: {
          'weightKg': double.parse(_weightController.text.trim()),
          'summary': _summaryController.text.trim(),
        },
        source: 'report',
        measuredAt: measuredAt,
      ),
    );
    tasks.add(
      _repo.addIndicator(
        type: 'glucose',
        payload: {
          'glucoseMmol': double.parse(_glucoseController.text.trim()),
          'summary': _summaryController.text.trim(),
        },
        source: 'report',
        measuredAt: measuredAt,
      ),
    );
    tasks.add(
      _repo.addIndicator(
        type: 'lipid',
        payload: {
          'tc': double.parse(_tcController.text.trim()),
          'ldl': double.parse(_ldlController.text.trim()),
          'summary': _summaryController.text.trim(),
        },
        source: 'report',
        measuredAt: measuredAt,
      ),
    );
    await Future.wait(tasks);

    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(const SnackBar(content: Text('报告关键值已保存到本地健康指标')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('报告识别'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _IntroCard(
              imageBytes: _imageBytes,
              imageName: _imageName,
              onPickGallery: () => _pickImage(ImageSource.gallery),
              onPickCamera: () => _pickImage(ImageSource.camera),
              onFillSample: _fillSample,
            ),
            const SizedBox(height: 16),
            _Panel(
              title: '报告结构化录入',
              subtitle: '当前版本支持本地上传 + 人工确认，后续可接入 OCR / 大模型',
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _systolicController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '收缩压'),
                            validator: _validateNumber,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _diastolicController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '舒张压'),
                            validator: _validateNumber,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: '体重（kg）'),
                            validator: _validateDecimal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _glucoseController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: '血糖（mmol/L）'),
                            validator: _validateDecimal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _tcController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: '总胆固醇'),
                            validator: _validateDecimal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _ldlController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'LDL-C'),
                            validator: _validateDecimal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _summaryController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '识别结论'),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('报告日期'),
                      subtitle: Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(_reportDate)),
                      trailing: TextButton(
                        onPressed: _pickDate,
                        child: const Text('选择'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('保存到本地'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _Panel(
              title: '最近识别结果',
              subtitle: '来自本地健康指标库',
              child: _RecentList(items: _recent),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateNumber(String? value) {
    if (int.tryParse(value?.trim() ?? '') == null) return '请输入数字';
    return null;
  }

  String? _validateDecimal(String? value) {
    if (double.tryParse(value?.trim() ?? '') == null) return '请输入数字';
    return null;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _reportDate,
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_reportDate));
    if (time == null) return;
    setState(() {
      _reportDate =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.imageBytes,
    required this.imageName,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onFillSample,
  });

  final Uint8List? imageBytes;
  final String? imageName;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onFillSample;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryBlue.withValues(alpha: 0.12), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final preview = Container(
            height: 220,
            decoration: BoxDecoration(
              color: AppTheme.pageBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: imageBytes == null
                ? const Center(
                    child: Text(
                      '请选择体检报告图片后开始录入',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(
                      imageBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
          );

          final actions = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('报告识别',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                '选择体检报告图片，人工确认关键指标后保存到本地健康库。后续接入 OCR / 多模态模型时可直接替换这一层。',
                style: TextStyle(color: AppTheme.muted, height: 1.5),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: onPickGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('选择图片'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onPickCamera,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('拍照'),
                  ),
                  TextButton.icon(
                    onPressed: onFillSample,
                    icon: const Icon(Icons.auto_fix_high_outlined),
                    label: const Text('示例填充'),
                  ),
                ],
              ),
              if (imageName != null) ...[
                const SizedBox(height: 10),
                Text('已选择：$imageName',
                    style: const TextStyle(color: AppTheme.muted)),
              ],
            ],
          );

          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: actions),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: preview),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    actions,
                    const SizedBox(height: 16),
                    preview,
                  ],
                );
        },
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

class _RecentList extends StatelessWidget {
  const _RecentList({required this.items});

  final List<HealthIndicatorEntry> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('暂无识别结果。', style: TextStyle(color: AppTheme.muted));
    }
    return Column(
      children: [
        for (final item in items)
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
    _ => Icons.fiber_manual_record_outlined,
  };
}
