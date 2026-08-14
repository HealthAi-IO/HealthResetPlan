import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import 'meal_input_args.dart';
import 'meal_slots.dart';
import '../../core/widgets/health_ui.dart';
import '../../core/widgets/numeric_picker_field.dart';
import 'personalized_menu_page.dart';

class FoodHubPage extends StatefulWidget {
  const FoodHubPage({super.key});

  @override
  State<FoodHubPage> createState() => _FoodHubPageState();
}

class _FoodHubPageState extends State<FoodHubPage> {
  final _repo = sl<HealthRepository>();

  bool _loading = true;
  String? _loadError;
  int _tabIndex = 0;
  DateTime _selectedDate = DateTime.now();
  List<MealRecordData> _meals = const [];
  List<MealRecipeData> _recipes = const [];
  List<PlanRecordData> _menuPlans = const [];
  UserProfileData? _profile;
  DailyNutritionTargets _targets = const DailyNutritionTargets(
    calories: 0,
    proteinG: 0,
    carbsG: 0,
    fatG: 0,
  );
  bool _budgetEnabled = false;
  double _monthlyBudget = 0;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChanged);
    _load(ensureRecipes: true);
  }

  @override
  void dispose() {
    _repo.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load(silent: true);

  Future<void> _load({bool silent = false, bool ensureRecipes = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final results = await (() async {
        if (ensureRecipes) await _repo.ensureStarterMealRecipes();
        final now = DateTime.now();
        return Future.wait<Object?>([
          _repo.loadMealsBetween(
            DateTime(now.year - 1, 1, 1),
            DateTime(now.year + 1, 1, 1),
          ),
          _repo.loadMealRecipes(),
          _repo.loadProfile(),
          _repo.loadMealSettings(),
          _repo.loadPlans(limit: 1000),
        ]);
      })()
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      final settings = results[3] as Map<String, dynamic>;
      setState(() {
        _meals = results[0] as List<MealRecordData>;
        _recipes = results[1] as List<MealRecipeData>;
        _profile = results[2] as UserProfileData?;
        _menuPlans = (results[4] as List<PlanRecordData>)
            .where((item) => item.type == 'meal')
            .toList();
        _targets = DailyNutritionTargets.fromProfile(
          _profile,
        );
        _budgetEnabled = settings['budgetEnabled'] == true;
        _monthlyBudget = (settings['monthlyBudget'] as num?)?.toDouble() ?? 0;
        _loadError = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = '暂时无法加载饮食数据，请检查网络后重试。';
        _loading = false;
      });
    }
  }

  List<MealRecordData> get _selectedMeals =>
      _meals.where((meal) => _sameDay(meal.eatenTime, _selectedDate)).toList()
        ..sort((a, b) => a.eatenAt.compareTo(b.eatenAt));

  Future<void> _openMeal(String mealType, {DateTime? date}) async {
    await context.push(
      '/meals/input',
      extra: MealInputArgs(
        mealType: mealType,
        eatenDate: date ?? _selectedDate,
      ),
    );
    await _load(silent: true);
  }

  Future<void> _editMeal(MealRecordData meal) async {
    await context.push('/meals/input', extra: meal);
    await _load(silent: true);
  }

  Future<void> _deleteMeal(MealRecordData meal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这一餐？'),
        content: Text('“${meal.name}”及对应饮食打卡会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deleteMealRecord(meal);
  }

  Future<void> _duplicateMeal(MealRecordData meal) async {
    final now = DateTime.now();
    await _repo.saveMealRecord(
      MealRecordData(
        clientId: HealthRepository.newClientId(),
        name: meal.name,
        mealType: meal.mealType,
        eatenAt: now.millisecondsSinceEpoch,
        imagePath: meal.imagePath,
        totalCalories: meal.totalCalories,
        proteinG: meal.proteinG,
        carbsG: meal.carbsG,
        fatG: meal.fatG,
        healthScore: meal.healthScore,
        glycemicLoad: meal.glycemicLoad,
        foods: meal.foods,
        nutrition: meal.nutrition,
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        portion: meal.portion,
        cost: meal.cost,
        diningType: meal.diningType,
        merchant: meal.merchant,
        note: meal.note,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到今天')),
      );
    }
  }

  Future<void> _showBudgetDialog() async {
    final controller = TextEditingController(
      text: _monthlyBudget > 0 ? _monthlyBudget.toStringAsFixed(0) : '',
    );
    var enabled = _budgetEnabled;
    String? errorText;
    final result = await showDialog<(bool, double)?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final value = double.tryParse(controller.text);
          return AlertDialog(
            title: const Text('饮食预算'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开启每月预算'),
                  value: enabled,
                  onChanged: (value) => setDialogState(() {
                    enabled = value;
                    errorText = null;
                  }),
                ),
                if (enabled) ...[
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: '每月预算',
                      suffixText: '元',
                      hintText: '请输入 100～100000',
                      errorText: errorText,
                    ),
                    onChanged: (_) => setDialogState(() => errorText = null),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final amount in const [1000, 2000, 3000, 5000])
                        ActionChip(
                          label: Text('$amount 元'),
                          onPressed: () => setDialogState(() {
                            controller.text = '$amount';
                            errorText = null;
                          }),
                        ),
                    ],
                  ),
                  if (value != null && value >= 100 && value <= 100000) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '约每天 ${value / 30 >= 100 ? (value / 30).toStringAsFixed(0) : (value / 30).toStringAsFixed(1)} 元',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ],
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (!enabled) {
                    Navigator.pop(context, (false, 0));
                    return;
                  }
                  final budget = double.tryParse(controller.text);
                  if (budget == null || budget < 100 || budget > 100000) {
                    setDialogState(
                      () => errorText = '请输入 100～100000 元',
                    );
                    return;
                  }
                  Navigator.pop(context, (true, budget));
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    await Future<void>.delayed(kThemeAnimationDuration);
    controller.dispose();
    if (result == null) return;
    await _repo.saveMealSettings({
      'budgetEnabled': result.$1,
      'monthlyBudget': result.$2,
    });
  }

  Future<void> _toggleFavorite(MealRecipeData recipe) async {
    await _repo.saveMealRecipe(
      recipe.copyWith(isFavorite: !recipe.isFavorite),
    );
  }

  Future<void> _recordRecipe(MealRecipeData recipe) async {
    final now = DateTime.now();
    final draft = MealRecordData(
      clientId: HealthRepository.newClientId(),
      name: recipe.name,
      mealType: _defaultMealType(),
      eatenAt: now.millisecondsSinceEpoch,
      imagePath: '',
      totalCalories: recipe.calories,
      proteinG: recipe.proteinG,
      carbsG: recipe.carbsG,
      fatG: recipe.fatG,
      healthScore: 0,
      glycemicLoad: 0,
      foods: [
        MealFoodItem(
          name: recipe.name,
          weightG: 0,
          calories: recipe.calories,
        ),
      ],
      nutrition: {
        'proteinG': recipe.proteinG,
        'carbsG': recipe.carbsG,
        'fatG': recipe.fatG,
      },
      createdAt: now.millisecondsSinceEpoch,
      updatedAt: now.millisecondsSinceEpoch,
    );
    Navigator.pop(context);
    await context.push('/meals/input', extra: draft);
    await _load(silent: true);
  }

  Future<void> _createRecipe() async {
    final result = await showDialog<MealRecipeData>(
      context: context,
      builder: (context) => const _RecipeEditorDialog(),
    );
    if (result == null) return;
    await _repo.saveMealRecipe(result);
  }

  Future<void> _openPersonalizedMenu() async {
    final profile = _profile;
    if (profile == null || !profile.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在“我的”完善基础档案')),
      );
      return;
    }
    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PersonalizedMenuPage(
          profile: profile,
          targets: _targets,
        ),
      ),
    );
    if (applied == true) await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null && _meals.isEmpty && _recipes.isEmpty) {
      return _MealLoadFailureView(onRetry: () => _load(ensureRecipes: true));
    }
    final view = switch (_tabIndex) {
      1 => _FoodLedgerView(
          meals: _meals,
          budgetEnabled: _budgetEnabled,
          monthlyBudget: _monthlyBudget,
          onBudget: _showBudgetDialog,
          onEdit: _editMeal,
          onDelete: _deleteMeal,
          onDuplicate: _duplicateMeal,
        ),
      2 => _RecipeBookView(
          recipes: _recipes,
          menuPlans: _menuPlans,
          onPersonalize: _openPersonalizedMenu,
          onCreate: _createRecipe,
          onFavorite: _toggleFavorite,
          onOpen: (recipe) => _showRecipe(context, recipe),
        ),
      3 => _FoodTrendView(meals: _meals, targets: _targets),
      _ => _TodayFoodView(
          selectedDate: _selectedDate,
          meals: _selectedMeals,
          allMeals: _meals,
          targets: _targets,
          onDateChanged: (value) => setState(() => _selectedDate = value),
          onAdd: _openMeal,
          onEdit: _editMeal,
        ),
    };
    return Column(
      children: [
        HealthPageHeader(
          title: '今日饮食',
          subtitle: DateFormat('M月d日 · EEEE', 'zh_CN').format(_selectedDate),
          action: IconButton(
            tooltip: '饮食预算',
            onPressed: _showBudgetDialog,
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('今日')),
              ButtonSegment(value: 1, label: Text('账本')),
              ButtonSegment(value: 2, label: Text('菜谱')),
              ButtonSegment(value: 3, label: Text('趋势')),
            ],
            selected: {_tabIndex},
            onSelectionChanged: (value) {
              setState(() => _tabIndex = value.first);
            },
          ),
        ),
        if (_loadError != null)
          _MealLoadErrorBanner(onRetry: () => _load(ensureRecipes: true)),
        const SizedBox(height: 8),
        Expanded(child: view),
      ],
    );
  }

  void _showRecipe(BuildContext context, MealRecipeData recipe) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        maxChildSize: 0.94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Row(children: [
              Expanded(
                child: Text(recipe.name,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: recipe.isFavorite ? '取消收藏' : '收藏',
                onPressed: () {
                  _toggleFavorite(recipe);
                  Navigator.pop(context);
                },
                icon: Icon(
                  recipe.isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: recipe.isFavorite ? Colors.redAccent : null,
                ),
              ),
            ]),
            Text(
              '${recipe.category} · ${recipe.durationMinutes} 分钟 · ${recipe.difficulty}',
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 18),
            _RecipeNutrition(recipe: recipe),
            const SizedBox(height: 22),
            const Text('食材',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final item in recipe.ingredients)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, size: 20),
                title: Text(item),
              ),
            const SizedBox(height: 14),
            const Text('步骤',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (var i = 0; i < recipe.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(radius: 13, child: Text('${i + 1}')),
                      const SizedBox(width: 10),
                      Expanded(child: Text(recipe.steps[i])),
                    ]),
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _recordRecipe(recipe),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('记为一餐'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealLoadFailureView extends StatelessWidget {
  const _MealLoadFailureView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 40,
                color: AppTheme.muted,
              ),
              const SizedBox(height: 12),
              const Text('暂时无法加载饮食数据'),
              const SizedBox(height: 6),
              Text('请检查网络后重试。', style: TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
}

class _MealLoadErrorBanner extends StatelessWidget {
  const _MealLoadErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: HealthPanel(
          color: AppTheme.softBlue,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.muted),
              const SizedBox(width: 8),
              const Expanded(child: Text('部分饮食数据未更新，请重试。')),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );
}

class _TodayFoodView extends StatelessWidget {
  const _TodayFoodView({
    required this.selectedDate,
    required this.meals,
    required this.allMeals,
    required this.targets,
    required this.onDateChanged,
    required this.onAdd,
    required this.onEdit,
  });

  final DateTime selectedDate;
  final List<MealRecordData> meals;
  final List<MealRecordData> allMeals;
  final DailyNutritionTargets targets;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<String> onAdd;
  final ValueChanged<MealRecordData> onEdit;

  @override
  Widget build(BuildContext context) {
    final calories = _sum(meals, (meal) => meal.totalCalories);
    final protein = _sum(meals, (meal) => meal.proteinG);
    final carbs = _sum(meals, (meal) => meal.carbsG);
    final fat = _sum(meals, (meal) => meal.fatG);
    return ListView(
      key: const PageStorageKey('food-today'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        _MealLedgerHero(
          calories: calories,
          protein: protein,
          carbs: carbs,
          fat: fat,
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: Text(
              _sameDay(selectedDate, DateTime.now()) ? '今天的餐食' : '餐食记录',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        MealSlots(meals: meals, onAdd: onAdd, onEdit: onEdit),
        const SizedBox(height: 18),
        FilledButton.icon(
            onPressed: () => onAdd(_defaultMealType()),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('拍照记录一餐')),
      ],
    );
  }
}

class _MealLedgerHero extends StatelessWidget {
  const _MealLedgerHero(
      {required this.calories,
      required this.protein,
      required this.carbs,
      required this.fat});
  final double calories, protein, carbs, fat;
  String _value(double value, String unit) =>
      value <= 0 ? '-- $unit' : '${value.toStringAsFixed(0)} $unit';
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            gradient: AppTheme.accentSoftGradient(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.softShadow,
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('饮食账本',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            '只记录真实吃过的食物',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 22),
          Text(_value(calories, '千卡'),
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          Row(children: [
            _Macro(label: '蛋白质', value: _value(protein, 'g')),
            _Macro(label: '碳水', value: _value(carbs, 'g')),
            _Macro(label: '脂肪', value: _value(fat, 'g'))
          ]),
        ]),
      );
}

class _Macro extends StatelessWidget {
  const _Macro({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700))
      ]));
}

class _FoodLedgerView extends StatefulWidget {
  const _FoodLedgerView({
    required this.meals,
    required this.budgetEnabled,
    required this.monthlyBudget,
    required this.onBudget,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
  });

  final List<MealRecordData> meals;
  final bool budgetEnabled;
  final double monthlyBudget;
  final VoidCallback onBudget;
  final ValueChanged<MealRecordData> onEdit;
  final ValueChanged<MealRecordData> onDelete;
  final ValueChanged<MealRecordData> onDuplicate;

  @override
  State<_FoodLedgerView> createState() => _FoodLedgerViewState();
}

class _FoodLedgerViewState extends State<_FoodLedgerView> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final meals = widget.meals
        .where((meal) =>
            meal.eatenTime.year == _month.year &&
            meal.eatenTime.month == _month.month)
        .toList();
    final cost = _sum(meals, (meal) => meal.cost);
    final grouped = <DateTime, List<MealRecordData>>{};
    for (final meal in meals) {
      final date = DateTime(
        meal.eatenTime.year,
        meal.eatenTime.month,
        meal.eatenTime.day,
      );
      grouped.putIfAbsent(date, () => []).add(meal);
    }
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView(
      key: const PageStorageKey('food-ledger'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        Row(children: [
          IconButton(
            tooltip: '上个月',
            onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1),
            ),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              DateFormat('yyyy年M月', 'zh_CN').format(_month),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: '下个月',
            onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month + 1),
            ),
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        const SizedBox(height: 10),
        _Section(
          child: Row(children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 30, color: AppTheme.deepBlue),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('本月饮食消费', style: TextStyle(color: AppTheme.muted)),
                    Text('¥${cost.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 25, fontWeight: FontWeight.w700)),
                    if (widget.budgetEnabled && widget.monthlyBudget > 0)
                      Text(
                        '预算 ¥${widget.monthlyBudget.toStringAsFixed(0)} · 剩余 ¥${math.max(0, widget.monthlyBudget - cost).toStringAsFixed(2)}',
                        style: TextStyle(color: AppTheme.muted),
                      ),
                  ]),
            ),
            TextButton(onPressed: widget.onBudget, child: const Text('设置')),
          ]),
        ),
        const SizedBox(height: 16),
        if (dates.isEmpty)
          _Section(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child:
                    Text('这个月还没有餐食记录', style: TextStyle(color: AppTheme.muted)),
              ),
            ),
          )
        else
          for (final date in dates) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                DateFormat('M月d日 EEEE', 'zh_CN').format(date),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final meal in grouped[date]!) ...[
              _MealTile(
                meal: meal,
                onTap: () => widget.onEdit(meal),
                menu: PopupMenuButton<String>(
                  tooltip: '餐食操作',
                  onSelected: (value) {
                    if (value == 'copy') widget.onDuplicate(meal);
                    if (value == 'delete') widget.onDelete(meal);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'copy', child: Text('复制到今天')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
      ],
    );
  }
}

class _PersonalizedMenuEntry extends StatelessWidget {
  const _PersonalizedMenuEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
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
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 30),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '定制专属 7 天菜单',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '结合健康档案生成，可随时换一道',
                          style: TextStyle(color: Color(0xFFFFF5EE)),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SavedMenuSection extends StatelessWidget {
  const _SavedMenuSection({required this.plans});

  final List<PlanRecordData> plans;

  @override
  Widget build(BuildContext context) {
    final sorted = [...plans]..sort((a, b) => a.planDate.compareTo(b.planDate));
    return Card(
      child: ExpansionTile(
        key: const PageStorageKey('saved-menu-section'),
        leading: const Icon(Icons.calendar_view_week_outlined),
        title: const Text('本周定制菜单'),
        subtitle: Text('${sorted.length} 天菜单，点击逐日查看'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final plan in sorted)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(DateFormat('M月d日 EEEE', 'zh_CN').format(plan.date)),
              subtitle: Text(
                _menuSummary(plan),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  String _menuSummary(PlanRecordData plan) {
    final parts = <String>[];
    for (final item in const [
      ('breakfast', '早'),
      ('lunch', '午'),
      ('dinner', '晚'),
      ('snack', '加餐'),
    ]) {
      final values = plan.payload[item.$1];
      if (values is List && values.isNotEmpty) {
        parts.add('${item.$2}：${values.first}');
      }
    }
    return parts.isEmpty ? '暂无菜单明细' : parts.join('  ·  ');
  }
}

class _RecipeBookView extends StatefulWidget {
  const _RecipeBookView({
    required this.recipes,
    required this.menuPlans,
    required this.onPersonalize,
    required this.onCreate,
    required this.onFavorite,
    required this.onOpen,
  });

  final List<MealRecipeData> recipes;
  final List<PlanRecordData> menuPlans;
  final VoidCallback onPersonalize;
  final VoidCallback onCreate;
  final ValueChanged<MealRecipeData> onFavorite;
  final ValueChanged<MealRecipeData> onOpen;

  @override
  State<_RecipeBookView> createState() => _RecipeBookViewState();
}

class _RecipeBookViewState extends State<_RecipeBookView> {
  String _query = '';
  String _category = '全部';

  @override
  Widget build(BuildContext context) {
    final categories = [
      '全部',
      ...{for (final item in widget.recipes) item.category}
    ];
    final recipes = widget.recipes.where((recipe) {
      return (_category == '全部' || recipe.category == _category) &&
          (_query.isEmpty || recipe.name.contains(_query));
    }).toList();
    return ListView(
      key: const PageStorageKey('food-recipes'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        _PersonalizedMenuEntry(onTap: widget.onPersonalize),
        if (widget.menuPlans.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SavedMenuSection(plans: widget.menuPlans),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                hintText: '搜索菜谱',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            tooltip: '创建菜谱',
            onPressed: widget.onCreate,
            icon: const Icon(Icons.add),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView.separated(
            key: const PageStorageKey('recipe-categories'),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) => ChoiceChip(
              label: Text(categories[index]),
              selected: _category == categories[index],
              onSelected: (_) => setState(() => _category = categories[index]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (recipes.isEmpty)
          const Center(child: Text('没有找到符合条件的菜谱'))
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 580
                      ? 2
                      : 1;
              return GridView.builder(
                key: const PageStorageKey('recipe-grid'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recipes.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 158,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (_, index) {
                  final recipe = recipes[index];
                  return _RecipeTile(
                    recipe: recipe,
                    onTap: () => widget.onOpen(recipe),
                    onFavorite: () => widget.onFavorite(recipe),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

class _FoodTrendView extends StatefulWidget {
  const _FoodTrendView({required this.meals, required this.targets});

  final List<MealRecordData> meals;
  final DailyNutritionTargets targets;

  @override
  State<_FoodTrendView> createState() => _FoodTrendViewState();
}

class _FoodTrendViewState extends State<_FoodTrendView> {
  String _period = 'week';
  String _metric = 'calories';

  @override
  Widget build(BuildContext context) {
    final points = _trendPoints(widget.meals, _period, _metric);
    final maxValue =
        points.fold<double>(1, (max, item) => math.max(max, item.$2));
    final target = switch (_metric) {
      'protein' => widget.targets.proteinG,
      'carbs' => widget.targets.carbsG,
      'fat' => widget.targets.fatG,
      'cost' => 0,
      _ => widget.targets.calories,
    };
    final sources = <String, double>{};
    for (final meal in _periodMeals(widget.meals, _period)) {
      for (final food in meal.foods) {
        sources[food.name] = (sources[food.name] ?? 0) + food.calories;
      }
    }
    final ranked = sources.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ListView(
      key: const PageStorageKey('food-trends'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        Row(children: [
          const Expanded(
            child: Text('饮食趋势',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'week', label: Text('周')),
              ButtonSegment(value: 'month', label: Text('月')),
              ButtonSegment(value: 'year', label: Text('年')),
            ],
            selected: {_period},
            onSelectionChanged: (value) =>
                setState(() => _period = value.first),
          ),
        ]),
        const SizedBox(height: 14),
        _Section(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in const [
                  ('calories', '热量'),
                  ('carbs', '碳水'),
                  ('protein', '蛋白质'),
                  ('fat', '脂肪'),
                  ('cost', '消费'),
                ])
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: _metric == item.$1,
                    onSelected: (_) => setState(() => _metric = item.$1),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(constraints.maxWidth, points.length * 38),
                  height: 210,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final point in points)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  point.$2.toStringAsFixed(0),
                                  style: const TextStyle(fontSize: 10),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  height:
                                      math.max(4, 145 * point.$2 / maxValue),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(point.$1,
                                    style: TextStyle(
                                        color: AppTheme.muted, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (target > 0)
              Text('每日参考目标：${target.toStringAsFixed(0)}',
                  style: TextStyle(color: AppTheme.muted)),
          ]),
        ),
        const SizedBox(height: 14),
        _TrendGuidance(
            meals: _periodMeals(widget.meals, _period),
            targets: widget.targets),
        const SizedBox(height: 14),
        _Section(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('热量来源排行',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (ranked.isEmpty)
              Text('记录餐食后会显示主要食物来源', style: TextStyle(color: AppTheme.muted))
            else
              for (var i = 0; i < math.min(5, ranked.length); i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(ranked[i].key),
                  trailing: Text('${ranked[i].value.toStringAsFixed(0)} kcal'),
                ),
          ]),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _WeekMealStrip extends StatelessWidget {
  const _WeekMealStrip({
    required this.selectedDate,
    required this.meals,
    required this.onChanged,
  });

  final DateTime selectedDate;
  final List<MealRecordData> meals;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final start =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day)
            .subtract(Duration(days: selectedDate.weekday % 7));
    final days = [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
    return _Section(
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text(
              DateFormat('M月', 'zh_CN').format(selectedDate),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: '选择日期',
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDate: selectedDate,
              );
              if (picked != null) onChanged(picked);
            },
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (final day in days)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(day),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 88,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _sameDay(day, selectedDate)
                        ? AppTheme.primaryBlue.withValues(alpha: 0.12)
                        : Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _sameDay(day, selectedDate)
                          ? AppTheme.primaryBlue
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(DateFormat('E', 'zh_CN').format(day),
                            style: const TextStyle(fontSize: 11)),
                        const SizedBox(height: 5),
                        _DayFoodPreview(
                          meals: meals
                              .where((meal) => _sameDay(meal.eatenTime, day))
                              .toList(),
                        ),
                        const SizedBox(height: 4),
                        Text('${day.day}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ]),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _DayFoodPreview extends StatelessWidget {
  const _DayFoodPreview({required this.meals});

  final List<MealRecordData> meals;

  @override
  Widget build(BuildContext context) {
    final image = meals.where((meal) => meal.imagePath.isNotEmpty).firstOrNull;
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: _MealImage(path: image.imagePath, width: 34, height: 28),
      );
    }
    return Container(
      width: 34,
      height: 28,
      decoration: BoxDecoration(
        color: meals.isEmpty
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : AppTheme.primaryBlue,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        meals.isEmpty ? Icons.remove : Icons.restaurant,
        size: 15,
        color: meals.isEmpty ? AppTheme.muted : Colors.white,
      ),
    );
  }
}

class _MealTile extends StatelessWidget {
  const _MealTile({required this.meal, required this.onTap, this.menu});

  final MealRecordData meal;
  final VoidCallback onTap;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppTheme.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: meal.imagePath.isEmpty
                  ? Container(
                      width: 66,
                      height: 66,
                      color: AppTheme.primaryBlue.withValues(alpha: 0.10),
                      child: Icon(Icons.restaurant, color: AppTheme.deepBlue),
                    )
                  : _MealImage(path: meal.imagePath, width: 66, height: 66),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(meal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('HH:mm').format(meal.eatenTime)} · ${meal.mealLabel} · ${_diningLabel(meal.diningType)}',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${meal.totalCalories.toStringAsFixed(0)} kcal  蛋白质 ${meal.proteinG.toStringAsFixed(0)}g${meal.cost > 0 ? '  ￥${meal.cost.toStringAsFixed(2)}' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ]),
            ),
            menu ?? const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

class _MealImage extends StatelessWidget {
  const _MealImage(
      {required this.path, required this.width, required this.height});

  final String path;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final base =
        sl<ApiClient>().dio.options.baseUrl.replaceFirst(RegExp(r'/$'), '');
    final token = UserSession.instance.accessToken;
    return Image.network(
      '$base/files/content?objectKey=${Uri.encodeQueryComponent(path)}',
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: const Icon(Icons.restaurant_outlined),
      ),
    );
  }
}

// ignore: unused_element
class _FoodGuidance extends StatelessWidget {
  const _FoodGuidance({
    required this.calories,
    required this.targetCalories,
    required this.protein,
    required this.targetProtein,
    required this.fat,
    required this.targetFat,
  });

  final double calories;
  final double targetCalories;
  final double protein;
  final double targetProtein;
  final double fat;
  final double targetFat;

  @override
  Widget build(BuildContext context) {
    final text = calories == 0
        ? '记录第一餐后，这里会根据当天摄入给出提示。'
        : targetCalories > 0 && calories > targetCalories
            ? '今天热量已超过参考目标，下一餐可优先选择清淡蔬菜和适量蛋白质。'
            : targetProtein > 0 && protein < targetProtein * 0.6
                ? '今天蛋白质摄入偏少，下一餐可考虑鱼、蛋、奶、豆制品或瘦肉。'
                : targetFat > 0 && fat > targetFat
                    ? '今天脂肪摄入偏高，下一餐建议减少油炸食品和高脂酱料。'
                    : '今天的记录整体平稳，继续注意食物种类和分量。';
    return _Section(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lightbulb_outline, color: AppTheme.deepBlue),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('饮食提示', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(text, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 4),
            Text('仅供健康管理参考，不构成医疗建议。',
                style: TextStyle(color: AppTheme.muted, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}

class _TrendGuidance extends StatelessWidget {
  const _TrendGuidance({required this.meals, required this.targets});

  final List<MealRecordData> meals;
  final DailyNutritionTargets targets;

  @override
  Widget build(BuildContext context) {
    final days =
        {for (final meal in meals) DateUtils.dateOnly(meal.eatenTime)}.length;
    final protein = _sum(meals, (meal) => meal.proteinG);
    final average = days == 0 ? 0 : protein / days;
    final text = days == 0
        ? '还没有足够的饮食记录，连续记录后会形成趋势。'
        : targets.proteinG > 0 && average < targets.proteinG * 0.7
            ? '这段时间蛋白质平均摄入偏低，可适量增加鱼、蛋、奶、豆制品或瘦肉。'
            : '这段时间已有 $days 天饮食记录，继续记录有助于看清长期变化。';
    return _Section(
      child: Row(children: [
        Icon(Icons.tips_and_updates_outlined, color: AppTheme.deepBlue),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
      ]),
    );
  }
}

// ignore: unused_element
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  final String label;
  final double value;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        SizedBox(width: 48, child: Text(label)),
        Expanded(
          child: LinearProgressIndicator(
            value: target <= 0 ? 0 : (value / target).clamp(0, 1),
            minHeight: 8,
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
            '${value.toStringAsFixed(0)}/${target <= 0 ? '--' : target.toStringAsFixed(0)}g',
            style: const TextStyle(fontSize: 11)),
      ]),
    ]);
  }
}

class _RecipeTile extends StatelessWidget {
  const _RecipeTile({
    required this.recipe,
    required this.onTap,
    required this.onFavorite,
  });

  final MealRecipeData recipe;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppTheme.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    Icon(Icons.soup_kitchen_outlined, color: AppTheme.deepBlue),
              ),
              const Spacer(),
              IconButton(
                tooltip: recipe.isFavorite ? '取消收藏' : '收藏',
                onPressed: onFavorite,
                icon: Icon(
                  recipe.isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: recipe.isFavorite ? Colors.redAccent : null,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(recipe.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(
              '${recipe.category} · ${recipe.durationMinutes}分钟 · ${recipe.calories.toStringAsFixed(0)} kcal',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RecipeNutrition extends StatelessWidget {
  const _RecipeNutrition({required this.recipe});

  final MealRecipeData recipe;

  @override
  Widget build(BuildContext context) {
    return _Section(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Metric('热量', recipe.calories, 'kcal'),
          _Metric('碳水', recipe.carbsG, 'g'),
          _Metric('蛋白质', recipe.proteinG, 'g'),
          _Metric('脂肪', recipe.fatG, 'g'),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.unit);

  final String label;
  final double value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value.toStringAsFixed(0),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      Text('$label $unit',
          style: TextStyle(color: AppTheme.muted, fontSize: 11)),
    ]);
  }
}

// ignore: unused_element
class _EmptyFood extends StatelessWidget {
  const _EmptyFood({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return _Section(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(children: [
          Icon(Icons.no_food_outlined, size: 38, color: AppTheme.muted),
          const SizedBox(height: 10),
          const Text('这一天还没有记录饮食'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('添加第一餐'),
          ),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: child,
    );
  }
}

class _RecipeEditorDialog extends StatefulWidget {
  const _RecipeEditorDialog();

  @override
  State<_RecipeEditorDialog> createState() => _RecipeEditorDialogState();
}

class _RecipeEditorDialogState extends State<_RecipeEditorDialog> {
  final _name = TextEditingController();
  final _category = TextEditingController(text: '家常菜');
  final _duration = TextEditingController(text: '20');
  final _ingredients = TextEditingController();
  final _steps = TextEditingController();
  final _calories = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _duration.dispose();
    _ingredients.dispose();
    _steps.dispose();
    _calories.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('创建我的菜谱'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '菜谱名称')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _category,
                      decoration: const InputDecoration(labelText: '分类'))),
              const SizedBox(width: 10),
              Expanded(
                child: NumericPickerField(
                  controller: _duration,
                  label: '用时',
                  unit: '分钟',
                  min: 5,
                  max: 480,
                  step: 5,
                  initialValue: 30,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _ingredients,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '食材，每行一项'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _steps,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '步骤，每行一步'),
            ),
            const SizedBox(height: 10),
            NumericPickerField(
              controller: _calories,
              label: '每份热量（选填）',
              unit: 'kcal',
              min: 0,
              max: 5000,
              step: 10,
              initialValue: 500,
              optional: true,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty ||
                _ingredients.text.trim().isEmpty ||
                _steps.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请填写菜谱名称、食材和步骤')),
              );
              return;
            }
            final now = DateTime.now().millisecondsSinceEpoch;
            Navigator.pop(
              context,
              MealRecipeData(
                clientId: HealthRepository.newClientId(),
                name: _name.text.trim(),
                category: _category.text.trim().isEmpty
                    ? '家常菜'
                    : _category.text.trim(),
                durationMinutes: int.tryParse(_duration.text) ?? 20,
                difficulty: '自定义',
                ingredients: _ingredients.text
                    .split('\n')
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList(),
                steps: _steps.text
                    .split('\n')
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList(),
                calories: double.tryParse(_calories.text) ?? 0,
                proteinG: 0,
                carbsG: 0,
                fatG: 0,
                isFavorite: true,
                isCustom: true,
                createdAt: now,
                updatedAt: now,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

List<(String, double)> _trendPoints(
  List<MealRecordData> meals,
  String period,
  String metric,
) {
  double value(MealRecordData meal) => switch (metric) {
        'protein' => meal.proteinG,
        'carbs' => meal.carbsG,
        'fat' => meal.fatG,
        'cost' => meal.cost,
        _ => meal.totalCalories,
      };
  final now = DateTime.now();
  if (period == 'year') {
    return [
      for (var i = 1; i <= 12; i++)
        (
          '$i月',
          _sum(
            meals.where((meal) =>
                meal.eatenTime.year == now.year && meal.eatenTime.month == i),
            value,
          ),
        ),
    ];
  }
  final count =
      period == 'month' ? DateUtils.getDaysInMonth(now.year, now.month) : 7;
  final start = period == 'month'
      ? DateTime(now.year, now.month, 1)
      : DateUtils.dateOnly(now).subtract(const Duration(days: 6));
  return [
    for (var i = 0; i < count; i++)
      (
        period == 'month'
            ? '${i + 1}'
            : DateFormat('E', 'zh_CN').format(start.add(Duration(days: i))),
        _sum(
          meals.where(
              (meal) => _sameDay(meal.eatenTime, start.add(Duration(days: i)))),
          value,
        ),
      ),
  ];
}

List<MealRecordData> _periodMeals(List<MealRecordData> meals, String period) {
  final now = DateTime.now();
  final start = switch (period) {
    'year' => DateTime(now.year, 1, 1),
    'month' => DateTime(now.year, now.month, 1),
    _ => DateUtils.dateOnly(now).subtract(const Duration(days: 6)),
  };
  return meals.where((meal) => !meal.eatenTime.isBefore(start)).toList();
}

double _sum(
  Iterable<MealRecordData> meals,
  double Function(MealRecordData meal) value,
) =>
    meals.fold(0, (sum, meal) => sum + value(meal));

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _defaultMealType() {
  final hour = DateTime.now().hour;
  if (hour < 10) return 'breakfast';
  if (hour < 15) return 'lunch';
  if (hour < 21) return 'dinner';
  return 'late_night';
}

String _diningLabel(String value) => switch (value) {
      'takeout' => '外卖',
      'restaurant' => '堂食',
      'snack' => '零食',
      'other' => '其他',
      _ => '自制',
    };
