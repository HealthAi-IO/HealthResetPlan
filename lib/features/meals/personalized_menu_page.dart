import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/ai_api.dart';
import '../../core/privacy/ai_consent_gate.dart';
import '../../core/widgets/ai_content_notice.dart';
import '../../core/widgets/numeric_picker_field.dart';

class PersonalizedMenuPage extends StatefulWidget {
  const PersonalizedMenuPage({
    super.key,
    required this.profile,
    required this.targets,
  });

  final UserProfileData profile;
  final DailyNutritionTargets targets;

  @override
  State<PersonalizedMenuPage> createState() => _PersonalizedMenuPageState();
}

class _PersonalizedMenuPageState extends State<PersonalizedMenuPage> {
  final _api = sl<AiApi>();
  final _repo = sl<HealthRepository>();
  final _allergies = TextEditingController();
  final _dislikedFoods = TextEditingController();
  final _budget = TextEditingController();
  final _cookingMinutes = TextEditingController(text: '30');

  bool _generating = false;
  String? _error;
  String _provider = 'qwen';
  Map<String, dynamic>? _menu;

  @override
  void dispose() {
    _allergies.dispose();
    _dislikedFoods.dispose();
    _budget.dispose();
    _cookingMinutes.dispose();
    super.dispose();
  }

  List<String> _split(TextEditingController controller) => controller.text
      .split(RegExp(r'[,，、]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  Future<void> _generate() async {
    if (_generating) return;
    if (!await ensureAiConsent(context)) return;
    if (!mounted) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final profile = widget.profile;
      final result = await _api.generatePersonalizedMenu({
        'provider': _provider,
        'age': profile.age,
        'gender': profile.gender,
        'heightCm': profile.heightCm,
        'weightKg': profile.weightKg,
        'medicalHistory': profile.medicalHistory,
        'medications': profile.medications,
        'goal': profile.goal,
        'dietPreference': profile.dietPreference,
        'allergies': _split(_allergies),
        'dislikedFoods': _split(_dislikedFoods),
        'budgetPerDay': double.tryParse(_budget.text),
        'cookingMinutes': int.tryParse(_cookingMinutes.text),
        'equipment': const ['炒锅', '蒸锅'],
        'targetCalories': widget.targets.calories,
        'proteinG': widget.targets.proteinG,
        'carbsG': widget.targets.carbsG,
        'fatG': widget.targets.fatG,
        'startDate': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      });
      if (!mounted) return;
      setState(() {
        _provider = result.provider;
        _menu = result.data;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyAiError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _swap(int dayIndex, String mealType) async {
    final menu = _menu;
    final days = menu?['days'];
    if (menu == null || days is! List || _generating) return;
    final day = days.whereType<Map>().firstWhere(
          (item) => (item['dayIndex'] as num?)?.toInt() == dayIndex,
          orElse: () => <dynamic, dynamic>{},
        );
    final meals = day['meals'];
    if (meals is! Map || meals[mealType] is! Map) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final result = await _api.swapPersonalizedMeal({
        'provider': _provider,
        'dayIndex': dayIndex,
        'mealType': mealType,
        'currentMeal': Map<String, dynamic>.from(meals[mealType] as Map),
        'allergies': _split(_allergies),
        'dislikedFoods': _split(_dislikedFoods),
        'targetCalories': widget.targets.calories,
      });
      meals[mealType] = result.data;
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyAiError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _apply() async {
    final days = _menu?['days'];
    if (days is! List || days.length != 7) return;
    await _repo.applyPersonalizedMenu(days: days, provider: _provider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('7 天菜单已保存到饮食页面')),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final menu = _menu;
    return Scaffold(
      appBar: AppBar(title: const Text('定制 7 天菜单')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (menu == null) ...[
            const _MenuIntro(),
            const SizedBox(height: 16),
            TextField(
              controller: _allergies,
              decoration: const InputDecoration(
                labelText: '过敏食物（必填则严格避开）',
                hintText: '例如：花生、虾',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dislikedFoods,
              decoration: const InputDecoration(
                labelText: '不喜欢的食物',
                hintText: '例如：香菜、芹菜',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: NumericPickerField(
                    controller: _budget,
                    label: '每日预算',
                    unit: '元',
                    min: 1,
                    max: 1000,
                    step: 1,
                    optional: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NumericPickerField(
                    controller: _cookingMinutes,
                    label: '做饭时长',
                    unit: '分钟',
                    min: 5,
                    max: 240,
                    step: 5,
                    optional: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(_generating ? '正在生成 7 天菜单' : '预览我的 7 天菜单'),
            ),
          ] else ...[
            Text(
              '${menu['summary'] ?? '你的个性化菜单'}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '${menu['keyFocus'] ?? '按实际份量记录，热量为估算值'}',
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 14),
            for (final day in (menu['days'] as List).whereType<Map>())
              _MenuDayCard(
                day: day,
                disabled: _generating,
                onSwap: (mealType) => _swap(
                  (day['dayIndex'] as num?)?.toInt() ?? 1,
                  mealType,
                ),
              ),
            const AiContentNotice(feature: '个性化 7 天菜单'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _generating ? null : _apply,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('采用本周菜单'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }
}

class _MenuIntro extends StatelessWidget {
  const _MenuIntro();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppTheme.accentGradient(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.softShadow,
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.restaurant_menu, color: Colors.white, size: 30),
            SizedBox(height: 12),
            Text(
              '根据档案生成，先预览再采用',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '每餐给出食材克数；不满意可单独换菜，不影响其余安排。',
              style: TextStyle(color: Color(0xFFFFF5EE)),
            ),
          ],
        ),
      );
}

class _MenuDayCard extends StatelessWidget {
  const _MenuDayCard({
    required this.day,
    required this.disabled,
    required this.onSwap,
  });

  final Map<dynamic, dynamic> day;
  final bool disabled;
  final ValueChanged<String> onSwap;

  @override
  Widget build(BuildContext context) {
    final meals = day['meals'];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day['weekDay'] ?? ''}  ${day['date'] ?? ''}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (meals is Map)
              for (final type in ['breakfast', 'lunch', 'dinner', 'snack'])
                if (meals[type] is Map)
                  _MenuMealRow(
                    label: const {
                          'breakfast': '早餐',
                          'lunch': '午餐',
                          'dinner': '晚餐',
                          'snack': '加餐',
                        }[type] ??
                        type,
                    meal: meals[type] as Map,
                    onSwap: disabled ? null : () => onSwap(type),
                  ),
          ],
        ),
      ),
    );
  }
}

class _MenuMealRow extends StatelessWidget {
  const _MenuMealRow({
    required this.label,
    required this.meal,
    required this.onSwap,
  });

  final String label;
  final Map<dynamic, dynamic> meal;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(label, style: TextStyle(color: AppTheme.muted)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${meal['name'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${(meal['calories'] as num?)?.round() ?? 0} kcal',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onSwap, child: const Text('换一道')),
          ],
        ),
      );
}

String _friendlyAiError(Object error) {
  if (error is FormatException) return error.message;
  if (error is DioException) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final message =
        body is Map ? '${body['msg'] ?? body['message'] ?? ''}' : '';
    if (status == 404) return '个性化菜单接口尚未部署到当前服务器。';
    if (status == 401 || status == 403) return '登录或 AI 授权已失效，请重新登录后再试。';
    if (status == 429 || message.contains('额度')) return '今天的 AI 生成次数已用完。';
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'AI 响应超时，请稍后重试。';
    }
    if (message.isNotEmpty) return message;
    if (error.message?.isNotEmpty == true) return error.message!;
  }
  return '菜单生成失败，请稍后重试。';
}
