import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/ai_api.dart';
import '../../core/storage/report_image_storage.dart';

const _proteinColor = Color(0xFF19B43B);
const _carbColor = Color(0xFFF59E0B);
const _fatColor = Color(0xFFFACC15);

class MealInputArgs {
  const MealInputArgs({required this.mealType, required this.eatenDate});

  final String mealType;
  final DateTime eatenDate;
}

class MealRecordPage extends StatefulWidget {
  const MealRecordPage({
    super.key,
    this.mealType = 'lunch',
    this.eatenDate,
    this.record,
  });

  final String mealType;
  final DateTime? eatenDate;
  final MealRecordData? record;

  @override
  State<MealRecordPage> createState() => _MealRecordPageState();
}

class _MealRecordPageState extends State<MealRecordPage> {
  final _repo = sl<HealthRepository>();
  final _api = sl<AiApi>();
  final _picker = ImagePicker();
  final _nameCtrl = TextEditingController();

  late String _mealType;
  XFile? _image;
  bool _loading = false;
  List<MealFoodItem> _foods = const [];
  Map<String, dynamic> _nutrition = const {};
  double _totalCalories = 0;
  double _proteinG = 0;
  double _carbsG = 0;
  double _fatG = 0;
  double _healthScore = 0;
  double _glycemicLoad = 0;
  String _provider = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _mealType = record?.mealType ?? widget.mealType;
    if (record != null) {
      _nameCtrl.text = record.name;
      _foods = record.foods;
      _nutrition = record.nutrition;
      _totalCalories = record.totalCalories;
      _proteinG = record.proteinG;
      _carbsG = record.carbsG;
      _fatG = record.fatG;
      _healthScore = record.healthScore;
      _glycemicLoad = record.glycemicLoad;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (image == null) return;
    setState(() {
      _image = image;
      _loading = true;
      _error = null;
      _provider = '';
      _nameCtrl.clear();
      _foods = const [];
      _totalCalories = 0;
      _proteinG = 0;
      _carbsG = 0;
      _fatG = 0;
      _healthScore = 0;
      _glycemicLoad = 0;
      _nutrition = const {};
    });
    try {
      final result = await _api.analyzeVision(image: image, type: 'meal');
      if (!mounted) return;
      _provider = result.provider;
      _applyMealMap(result.structured);
    } on DioException catch (e) {
      if (!mounted) return;
      _clearRecognizedMeal(_friendlyError(e));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    } catch (_) {
      if (!mounted) return;
      const message = 'AI 已返回结果，但餐食数据不完整，暂时无法自动生成食材明细；请重拍完整食物或手动添加食材。';
      _clearRecognizedMeal(message, clearName: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyMealMap(Map<String, dynamic> data) {
    final foodsRaw = _firstValue(data, const [
      'foods',
      'ingredients',
      'items',
      'foodItems',
      '食材',
      '食材列表',
    ]);
    final foods = foodsRaw is List
        ? foodsRaw
            .whereType<Map>()
            .map((item) => MealFoodItem.fromJson(
                  item.map((key, value) => MapEntry('$key', value)),
                ))
            .toList()
        : <MealFoodItem>[];
    final nutrition = _asMap(data['nutrition']);
    final mealName =
        (_firstValue(data, const ['mealName', 'name', 'title', '餐单名称']) ??
                _nameCtrl.text)
            .toString()
            .trim();
    final totalCalories = _num(_firstValue(
      data,
      const ['totalCalories', 'calories', 'kcal', '总热量', '热量'],
    ));
    final hasMealName = mealName.isNotEmpty && mealName != '未命名餐单';
    final displayFoods = foods.isEmpty && (totalCalories > 0 || hasMealName)
        ? [
            MealFoodItem(
              name: mealName.isEmpty ? '识别餐食' : mealName,
              weightG: 0,
              calories: totalCalories,
            )
          ]
        : foods;
    setState(() {
      _nameCtrl.text = mealName;
      if (_nameCtrl.text.isEmpty) _nameCtrl.text = '未命名餐单';
      _foods = displayFoods;
      _totalCalories = totalCalories;
      _proteinG = _num(
          _firstValue(data, const ['proteinG', 'protein', '蛋白质']) ??
              nutrition['proteinG']);
      _carbsG = _num(
          _firstValue(data, const ['carbsG', 'carbs', '碳水化合物', '碳水']) ??
              nutrition['carbsG']);
      _fatG = _num(
          _firstValue(data, const ['fatG', 'fat', '脂肪']) ?? nutrition['fatG']);
      _healthScore =
          _num(_firstValue(data, const ['healthScore', 'score', '健康评分']))
              .clamp(0, 10)
              .toDouble();
      _glycemicLoad =
          _num(_firstValue(data, const ['glycemicLoad', 'gl', '血糖负荷']));
      _nutrition = {
        'proteinG': _proteinG,
        'carbsG': _carbsG,
        'fiberG': _num(nutrition['fiberG']),
        'sugarG': _num(nutrition['sugarG']),
        'fatG': _fatG,
        'saturatedFatG': _num(nutrition['saturatedFatG']),
        'monounsaturatedFatG': _num(nutrition['monounsaturatedFatG']),
        'polyunsaturatedFatG': _num(nutrition['polyunsaturatedFatG']),
        'transFatG': _num(nutrition['transFatG']),
        'cholesterolMg': _num(nutrition['cholesterolMg']),
      };
      _error = foods.isEmpty && displayFoods.isNotEmpty
          ? 'AI 只识别到餐名，未拆出食材明细；已生成一条可编辑记录，请手动校准重量和热量。'
          : displayFoods.isEmpty
              ? 'AI 已返回结果，但未拆出食材，请手动添加或重拍更清晰的餐食照片。'
              : null;
    });
  }

  void _clearRecognizedMeal(String message, {bool clearName = false}) {
    setState(() {
      _error = message;
      _provider = '';
      _foods = const [];
      _totalCalories = 0;
      _proteinG = 0;
      _carbsG = 0;
      _fatG = 0;
      _healthScore = 0;
      _glycemicLoad = 0;
      _nutrition = const {};
      if (clearName ||
          _nameCtrl.text.trim().isEmpty ||
          _nameCtrl.text == '未命名餐单') {
        _nameCtrl.text = '';
      }
    });
  }

  Future<void> _editFood(int index) async {
    final item = _foods[index];
    final nameCtrl = TextEditingController(text: item.name);
    final weightCtrl =
        TextEditingController(text: item.weightG.toStringAsFixed(0));
    final caloriesCtrl =
        TextEditingController(text: item.calories.toStringAsFixed(0));
    final result = await showDialog<MealFoodItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑食材'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '食材')),
          const SizedBox(height: 10),
          TextField(
            controller: weightCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '重量（克）'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: caloriesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '热量（kcal）'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              MealFoodItem(
                name:
                    nameCtrl.text.trim().isEmpty ? '食材' : nameCtrl.text.trim(),
                weightG: double.tryParse(weightCtrl.text) ?? item.weightG,
                calories: double.tryParse(caloriesCtrl.text) ?? item.calories,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    weightCtrl.dispose();
    caloriesCtrl.dispose();
    if (result == null) return;
    final next = [..._foods]..[index] = result;
    setState(() {
      _foods = next;
      _totalCalories = next.fold(0, (sum, item) => sum + item.calories);
      _error = null;
    });
  }

  Future<void> _addFood() async {
    final nameCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final caloriesCtrl = TextEditingController();
    final result = await showDialog<MealFoodItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加食材'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '食材')),
          const SizedBox(height: 10),
          TextField(
            controller: weightCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '重量（克）'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: caloriesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '热量（kcal）'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              MealFoodItem(
                name:
                    nameCtrl.text.trim().isEmpty ? '食材' : nameCtrl.text.trim(),
                weightG: double.tryParse(weightCtrl.text) ?? 0,
                calories: double.tryParse(caloriesCtrl.text) ?? 0,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    weightCtrl.dispose();
    caloriesCtrl.dispose();
    if (result == null) return;
    final next = [..._foods, result];
    setState(() {
      _error = null;
      _foods = next;
      _totalCalories = next.fold(0, (sum, item) => sum + item.calories);
      if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = '手动餐单';
    });
  }

  Future<void> _save() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final baseDate =
        widget.record?.eatenTime ?? widget.eatenDate ?? DateTime.now();
    final clientId = widget.record?.clientId ?? HealthRepository.newClientId();
    final imagePath = _image == null
        ? widget.record?.imagePath ?? ''
        : await persistReportImage(_image!, clientId);
    final record = MealRecordData(
      id: widget.record?.id,
      clientId: clientId,
      name: _nameCtrl.text.trim().isEmpty ? '未命名餐单' : _nameCtrl.text.trim(),
      mealType: _mealType,
      eatenAt: baseDate.millisecondsSinceEpoch,
      imagePath: imagePath,
      totalCalories: _totalCalories,
      proteinG: _proteinG,
      carbsG: _carbsG,
      fatG: _fatG,
      healthScore: _healthScore,
      glycemicLoad: _glycemicLoad,
      foods: _foods,
      nutrition: _nutrition,
      createdAt: widget.record?.createdAt ?? now,
      updatedAt: now,
    );
    await _repo.saveMealRecord(record);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final canUseCamera = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return Scaffold(
      appBar: AppBar(title: const Text('记录餐食')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _UploadMealCard(
            image: _image,
            imageName: _image?.name ?? widget.record?.imagePath,
            loading: _loading,
            canUseCamera: canUseCamera,
            onCamera: () => _pick(ImageSource.camera),
            onGallery: () => _pick(ImageSource.gallery),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _MealErrorCard(message: _error!),
          ],
          const SizedBox(height: 14),
          _MealSummaryCard(
            nameCtrl: _nameCtrl,
            mealType: _mealType,
            onMealTypeChanged: (value) => setState(() => _mealType = value),
            totalCalories: _totalCalories,
            proteinG: _proteinG,
            carbsG: _carbsG,
            fatG: _fatG,
            healthScore: _healthScore,
          ),
          const SizedBox(height: 14),
          _FoodListCard(
            foods: _foods,
            onEdit: _editFood,
            onAdd: _addFood,
          ),
          if (_provider.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('识别服务：$_provider',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _loading || _foods.isEmpty ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存到本餐'),
          ),
        ),
      ),
    );
  }

  String _friendlyError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      return (data['message'] ?? data['msg'])?.toString() ?? 'AI 识别失败';
    }
    return '网络或服务请求失败，请稍后重试；也可以先手动添加食材。';
  }
}

class MealDetailPage extends StatefulWidget {
  const MealDetailPage({super.key, required this.id});

  final int id;

  @override
  State<MealDetailPage> createState() => _MealDetailPageState();
}

class _MealDetailPageState extends State<MealDetailPage> {
  final _repo = sl<HealthRepository>();
  MealRecordData? _record;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final record = await _repo.loadMealRecord(widget.id);
    if (!mounted) return;
    setState(() => _record = record);
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    if (record == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final totalMacro = record.proteinG + record.carbsG + record.fatG;
    return Scaffold(
      appBar: AppBar(title: Text(record.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _GlycemicLoadCard(value: record.glycemicLoad),
          const SizedBox(height: 14),
          _NutritionRings(
            proteinG: record.proteinG,
            carbsG: record.carbsG,
            fatG: record.fatG,
            totalMacro: totalMacro <= 0 ? 1 : totalMacro,
          ),
          const SizedBox(height: 14),
          _NutritionTable(nutrition: record.nutrition),
          const SizedBox(height: 14),
          _FoodListCard(foods: record.foods, onEdit: null),
        ],
      ),
    );
  }
}

class _UploadMealCard extends StatelessWidget {
  const _UploadMealCard({
    required this.image,
    required this.imageName,
    required this.loading,
    required this.canUseCamera,
    required this.onCamera,
    required this.onGallery,
  });

  final XFile? image;
  final String? imageName;
  final bool loading;
  final bool canUseCamera;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return _MealCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('拍照识别食物热量',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('上传餐食照片后，AI 会拆分食材、估算重量、热量和营养素。',
            style: TextStyle(color: AppTheme.muted, height: 1.4)),
        const SizedBox(height: 6),
        const Text(
          '图片需小于 10MB，建议光线充足、食物完整入镜；系统会自动压缩后上传。',
          style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (canUseCamera)
            FilledButton.icon(
              onPressed: loading ? null : onCamera,
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: const Text('拍照'),
            ),
          OutlinedButton.icon(
            onPressed: loading ? null : onGallery,
            icon: const Icon(Icons.photo_library_outlined, size: 16),
            label: const Text('从相册选择'),
          ),
        ]),
        if (imageName != null && imageName!.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (image != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FutureBuilder<Uint8List>(
                future: image!.readAsBytes(),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return Container(
                      height: 150,
                      alignment: Alignment.center,
                      color: AppTheme.pageBg,
                      child: const CircularProgressIndicator(),
                    );
                  }
                  return Image.memory(
                    bytes,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(imageName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ],
        if (loading) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ],
      ]),
    );
  }
}

class _MealSummaryCard extends StatelessWidget {
  const _MealSummaryCard({
    required this.nameCtrl,
    required this.mealType,
    required this.onMealTypeChanged,
    required this.totalCalories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.healthScore,
  });

  final TextEditingController nameCtrl;
  final String mealType;
  final ValueChanged<String> onMealTypeChanged;
  final double totalCalories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double healthScore;

  @override
  Widget build(BuildContext context) {
    return _MealCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: '餐单名称'),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'breakfast', label: Text('早餐')),
            ButtonSegment(value: 'lunch', label: Text('午餐')),
            ButtonSegment(value: 'dinner', label: Text('晚餐')),
          ],
          selected: {mealType},
          onSelectionChanged: (values) => onMealTypeChanged(values.first),
        ),
        const SizedBox(height: 18),
        Row(children: [
          MacroRing(
            calories: totalCalories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            size: 120,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(children: [
              _MacroPill('蛋白质', proteinG, _proteinColor),
              const SizedBox(height: 8),
              _MacroPill('碳水化合物', carbsG, _carbColor),
              const SizedBox(height: 8),
              _MacroPill('脂肪', fatG, _fatColor),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          const Icon(Icons.favorite, color: Colors.pinkAccent, size: 34),
          const SizedBox(width: 14),
          const Expanded(
              child:
                  Text('健康评分', style: TextStyle(fontWeight: FontWeight.w800))),
          Text('${healthScore.toStringAsFixed(1)} / 10',
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (healthScore / 10).clamp(0, 1),
          color: Colors.green,
          minHeight: 7,
          borderRadius: BorderRadius.circular(99),
        ),
      ]),
    );
  }
}

class _FoodListCard extends StatelessWidget {
  const _FoodListCard({
    required this.foods,
    required this.onEdit,
    this.onAdd,
  });

  final List<MealFoodItem> foods;
  final void Function(int index)? onEdit;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return _MealCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('成分',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          if (onAdd != null)
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加'),
            )
          else if (onEdit != null)
            const Text('点击条目编辑',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        if (foods.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.pageBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              '还没有识别到食材。请重新拍照/选择图片，或手动添加食材。',
              style: TextStyle(color: AppTheme.muted, height: 1.4),
            ),
          )
        else
          for (var i = 0; i < foods.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: onEdit == null ? null : () => onEdit!(i),
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.10),
                child: const Icon(Icons.restaurant_outlined,
                    color: AppTheme.deepBlue, size: 18),
              ),
              title: Text(foods[i].name,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${foods[i].weightG.toStringAsFixed(0)} 克'),
              trailing: Text('${foods[i].calories.toStringAsFixed(0)} kcal',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
      ]),
    );
  }
}

class _MealErrorCard extends StatelessWidget {
  const _MealErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, color: Colors.orange.shade800, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: Colors.orange.shade900, height: 1.4),
          ),
        ),
      ]),
    );
  }
}

class _GlycemicLoadCard extends StatelessWidget {
  const _GlycemicLoadCard({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final pos = (value / 30).clamp(0.0, 1.0);
    return _MealCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('血糖负荷',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          Text(value.toStringAsFixed(1),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 26),
        LayoutBuilder(builder: (_, c) {
          return Stack(clipBehavior: Clip.none, children: [
            Row(children: [
              Expanded(child: _GlBand(color: Colors.green)),
              Expanded(child: _GlBand(color: Colors.orange)),
              Expanded(child: _GlBand(color: Colors.redAccent)),
            ]),
            Positioned(
              left: (c.maxWidth - 18) * pos,
              top: -22,
              child: Column(children: [
                Text(value.toStringAsFixed(1),
                    style: const TextStyle(
                        color: Colors.orange, fontWeight: FontWeight.w800)),
                const Icon(Icons.arrow_drop_down,
                    color: Colors.orange, size: 28),
              ]),
            ),
          ]);
        }),
        const SizedBox(height: 12),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          Text('≤10\n低',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted)),
          Text('10-20\n中',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted)),
          Text('>20\n高',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted)),
        ]),
      ]),
    );
  }
}

class _NutritionRings extends StatelessWidget {
  const _NutritionRings({
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.totalMacro,
  });

  final double proteinG;
  final double carbsG;
  final double fatG;
  final double totalMacro;

  @override
  Widget build(BuildContext context) {
    return _MealCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('营养成分',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _SmallNutrientRing(
              '蛋白质', proteinG, proteinG / totalMacro, _proteinColor),
          _SmallNutrientRing('碳水化合物', carbsG, carbsG / totalMacro, _carbColor),
          _SmallNutrientRing('脂肪', fatG, fatG / totalMacro, _fatColor),
        ]),
      ]),
    );
  }
}

class _NutritionTable extends StatelessWidget {
  const _NutritionTable({required this.nutrition});

  final Map<String, dynamic> nutrition;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('蛋白质', 'proteinG', '克'),
      ('碳水化合物', 'carbsG', '克'),
      ('膳食纤维', 'fiberG', '克'),
      ('糖', 'sugarG', '克'),
      ('总脂肪', 'fatG', '克'),
      ('饱和脂肪', 'saturatedFatG', '克'),
      ('单不饱和脂肪', 'monounsaturatedFatG', '克'),
      ('多不饱和脂肪', 'polyunsaturatedFatG', '克'),
      ('反式脂肪', 'transFatG', '克'),
      ('胆固醇', 'cholesterolMg', '毫克'),
    ];
    return _MealCard(
      child: Column(children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Expanded(
                  child: Text(row.$1,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${_num(nutrition[row.$2]).toStringAsFixed(1)} ${row.$3}'),
            ]),
          ),
      ]),
    );
  }
}

class MacroRing extends StatelessWidget {
  const MacroRing({
    super.key,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.size = 98,
  });

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(size, size),
          painter: _MacroRingPainter(
            protein: proteinG,
            carbs: carbsG,
            fat: fatG,
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(calories.round().toString(),
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const Text('kcal', style: TextStyle(color: AppTheme.muted)),
        ]),
      ]),
    );
  }
}

class _MacroRingPainter extends CustomPainter {
  const _MacroRingPainter({
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final double protein;
  final double carbs;
  final double fat;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.095;
    final bg = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(stroke), -pi / 2, pi * 2, false, bg);
    final total = max(1, protein + carbs + fat);
    var start = -pi / 2;
    for (final item in [
      (protein, _proteinColor),
      (carbs, _carbColor),
      (fat, _fatColor),
    ]) {
      final sweep = pi * 2 * item.$1 / total;
      final paint = Paint()
        ..color = item.$2
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect.deflate(stroke), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _MacroRingPainter old) =>
      old.protein != protein || old.carbs != carbs || old.fat != fat;
}

class _SmallNutrientRing extends StatelessWidget {
  const _SmallNutrientRing(this.label, this.grams, this.value, this.color);

  final String label;
  final double grams;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        width: 82,
        height: 82,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(
            value: value.clamp(0, 1),
            strokeWidth: 6,
            color: color,
            backgroundColor: const Color(0xFFE5E7EB),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${grams.toStringAsFixed(1)}克',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text('${(value * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12)),
          ]),
        ]),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ]);
  }
}

class _MacroPill extends StatelessWidget {
  const _MacroPill(this.label, this.value, this.color);

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        CircleAvatar(radius: 7, backgroundColor: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w800))),
        Text('${value.toStringAsFixed(1)}克',
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

class _GlBand extends StatelessWidget {
  const _GlBand({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: child,
    );
  }
}

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.map((key, value) => MapEntry('$key', value));
  return <String, dynamic>{};
}

Object? _firstValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null) return value;
  }
  return null;
}

double _num(Object? raw) {
  if (raw is num) return raw.toDouble();
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch('${raw ?? ''}');
  return match == null ? 0 : double.tryParse(match.group(0)!) ?? 0;
}
