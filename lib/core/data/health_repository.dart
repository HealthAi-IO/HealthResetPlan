import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../storage/app_database.dart';
import 'health_models.dart';

class PlanBlockedException implements Exception {
  const PlanBlockedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HealthRepository extends ChangeNotifier {
  HealthRepository({required this.database});

  final AppDatabase database;
  bool _ready = false;
  static const _uuid = Uuid();

  static String newClientId() => _uuid.v4();

  Future<void> initialize() async {
    if (_ready) return;
    await database.open();
    await cleanupAiPlanReminders();
    await cleanupDuplicateReminders();
    _ready = true;
  }

  Future<HealthDashboardData> loadDashboard() async {
    // 每种指标类型各取最新 5 条，确保「今日数据」每类都能找到最新值
    const types = [
      'weight',
      'bp',
      'glucose',
      'heart_rate',
      'lipid',
      'spo2',
      'bmi',
    ];
    final perType = await Future.wait(
      types.map((t) => loadIndicators(type: t, limit: 5)),
    );
    final indicators = [for (final list in perType) ...list]
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));

    return HealthDashboardData(
      profile: await loadProfile(),
      indicators: indicators,
      plans: await loadPlansForDate(DateTime.now()),
      clockRecords: await loadClockRecords(limit: 18),
      reminders: await loadReminders(),
    );
  }

  Future<UserProfileData?> loadProfile() async {
    final db = await database.open();
    final rows = await db.query(
      'user_profile',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserProfileData.fromRow(rows.first);
  }

  Future<void> saveProfile(UserProfileData profile) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = profile.copyWith(
      userId: kLocalUserId,
      updatedAt: now,
      createdAt: profile.createdAt == 0 ? now : profile.createdAt,
      isDirty: 1,
    );
    final updated = await db.update(
      'user_profile',
      next.toRow(),
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
    );
    if (updated == 0) {
      await db.insert('user_profile', next.toRow());
    }
    notifyListeners();
  }

  Future<List<HealthIndicatorEntry>> loadIndicators({
    int limit = 50,
    String? type,
  }) async {
    final db = await database.open();
    final rows = await db.query(
      'health_indicator',
      where: type == null ? 'user_id = ?' : 'user_id = ? AND type = ?',
      whereArgs: type == null ? [kLocalUserId] : [kLocalUserId, type],
      orderBy: 'measured_at DESC',
      limit: limit,
    );
    return rows.map(HealthIndicatorEntry.fromRow).toList();
  }

  // 按日期加载指标（用于「最近指标」面板，避免固定 limit 遗漏数据）
  Future<List<HealthIndicatorEntry>> loadIndicatorsSince(DateTime since) async {
    final db = await database.open();
    final rows = await db.query(
      'health_indicator',
      where: 'user_id = ? AND measured_at >= ?',
      whereArgs: [kLocalUserId, since.millisecondsSinceEpoch],
      orderBy: 'measured_at DESC',
    );
    return rows.map(HealthIndicatorEntry.fromRow).toList();
  }

  Future<HealthTrendAlert?> loadPriorityHealthAlert() async {
    final entries = await loadIndicatorsSince(
      DateTime.now().subtract(const Duration(days: 7)),
    );
    if (entries.isEmpty) return null;
    final profile = await loadProfile();

    for (final entry in entries) {
      if (HealthSafety.isCriticalIndicator(entry.type, entry.payload)) {
        return HealthTrendAlert(
          type: entry.type,
          title: '检测到紧急健康风险',
          message: entry.type == 'bp'
              ? '本次血压达到危险范围，请立即就医，不要等待复测结果。'
              : '本次血氧达到危险范围，请立即就医。',
          isCritical: true,
          retestAfter: Duration.zero,
        );
      }
    }

    const priority = [
      'bp',
      'glucose',
      'spo2',
      'heart_rate',
      'lipid',
      'weight',
      'sleep',
      'steps',
    ];
    for (final type in priority) {
      final recent =
          entries.where((entry) => entry.type == type).take(2).toList();
      if (recent.length < 2 ||
          !recent.every((entry) => _isAbnormalEntry(entry, profile))) {
        continue;
      }
      return HealthTrendAlert(
        type: type,
        title: '${recent.first.label}连续异常',
        message: _trendAlertMessage(type),
        isCritical: false,
        retestAfter: type == 'bp'
            ? const Duration(minutes: 30)
            : const Duration(days: 1),
      );
    }
    return null;
  }

  bool _isAbnormalEntry(
    HealthIndicatorEntry entry,
    UserProfileData? profile,
  ) {
    final payload = entry.payload;
    return switch (entry.type) {
      'bp' => ((payload['systolic'] as num?)?.toDouble() ?? 0) >= 130 ||
          ((payload['diastolic'] as num?)?.toDouble() ?? 0) >= 80,
      'glucose' => (payload['mealType'] == 'postmeal'
          ? ((payload['glucoseMmol'] as num?)?.toDouble() ?? 0) >= 7.8
          : ((payload['glucoseMmol'] as num?)?.toDouble() ?? 0) >= 5.6),
      'spo2' => ((payload['spo2Pct'] as num?)?.toDouble() ?? 100) < 95,
      'heart_rate' => ((payload['bpm'] as num?)?.toDouble() ?? 70) < 60 ||
          ((payload['bpm'] as num?)?.toDouble() ?? 70) > 100,
      'lipid' => ((payload['tc'] as num?)?.toDouble() ?? 0) >= 5.18 ||
          ((payload['ldl'] as num?)?.toDouble() ?? 0) >= 3.37,
      'weight' => profile == null || profile.heightCm <= 0
          ? false
          : (() {
              final weight = (payload['weightKg'] as num?)?.toDouble() ?? 0;
              final height = profile.heightCm / 100;
              final bmi = height <= 0 ? 0 : weight / (height * height);
              return bmi > 0 && (bmi < 18.5 || bmi >= 24);
            })(),
      'sleep' => ((payload['sleepHours'] as num?)?.toDouble() ?? 8) < 7,
      'steps' => ((payload['steps'] as num?)?.toInt() ?? 7500) < 7500,
      _ => false,
    };
  }

  String _trendAlertMessage(String type) => switch (type) {
        'bp' => '7天内最近两次血压均偏高。请静坐5分钟，以正确姿势重新测量；如持续异常请咨询医生。',
        'glucose' => '7天内最近两次血糖均超出参考范围。请确认测量时段并于次日复测，持续异常请就医。',
        'spo2' => '7天内最近两次血氧偏低。请保持手指温暖、静止后复测，若伴呼吸困难请及时就医。',
        'heart_rate' => '7天内最近两次静息心率异常。请在安静状态下复测，若伴胸痛、晕厥请及时就医。',
        'lipid' => '最近两次血脂记录均超出参考范围，建议携带检查结果咨询医生。',
        'weight' => '最近两次体重对应的BMI超出参考范围，请结合长期趋势调整计划。',
        'sleep' => '最近两次睡眠均少于7小时，建议优先恢复规律作息。',
        'steps' => '最近两次步数均低于目标，可从短时步行开始逐步增加活动量。',
        _ => '最近两次记录均超出参考范围，建议复测并持续观察。',
      };

  Future<int> addIndicator({
    required String type,
    required Map<String, dynamic> payload,
    String source = 'manual',
    DateTime? measuredAt,
  }) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = HealthIndicatorEntry(
      clientId: _uuid.v4(),
      type: type,
      payload: payload,
      source: source,
      measuredAt: (measuredAt ?? DateTime.now()).millisecondsSinceEpoch,
      createdAt: now,
      updatedAt: now,
    );
    final id = await db.insert('health_indicator', entry.toRow());

    await _applyCriticalIndicatorSafety(type, db);

    if (type == 'weight' && payload['weightKg'] is num) {
      final profile = await loadProfile();
      if (profile != null) {
        final newWeight = (payload['weightKg'] as num).toDouble();
        final updatedProfile = profile.copyWith(
          weightKg: newWeight,
          updatedAt: now,
          isDirty: 1,
        );
        await db.update(
          'user_profile',
          updatedProfile.toRow(),
          where: 'user_id = ?',
          whereArgs: [kLocalUserId],
        );
        // 自动写入 BMI 指标记录（高度已知时）
        final bmiVal = updatedProfile.bmi;
        if (bmiVal > 0) {
          await db.insert(
            'health_indicator',
            HealthIndicatorEntry(
              clientId: _uuid.v4(),
              type: 'bmi',
              payload: {'bmiValue': double.parse(bmiVal.toStringAsFixed(2))},
              source: 'calculated',
              measuredAt: (measuredAt ?? DateTime.now()).millisecondsSinceEpoch,
              createdAt: now,
              updatedAt: now,
            ).toRow(),
          );
        }
      }
    }
    notifyListeners();
    return id;
  }

  Future<void> _applyCriticalIndicatorSafety(
    String type,
    AppDatabase db,
  ) async {
    if (type != 'bp' && type != 'spo2') return;
    final profile = await loadProfile();
    if (profile?.isComplete != true) return;
    final risk = await _assessRisk(profile!);
    if (risk.crisisBp || risk.dangerSpo2) {
      await db.delete(
        'plan',
        where: 'user_id = ? AND type = ?',
        whereArgs: [kLocalUserId, 'exercise'],
      );
    }
    await _saveRiskPlan(db, risk);
  }

  Future<List<PlanRecordData>> loadPlans({int limit = 30}) async {
    final db = await database.open();
    final rows = await db.query(
      'plan',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
      orderBy: 'plan_date ASC, type ASC',
      limit: limit,
    );
    return rows.map(PlanRecordData.fromRow).toList();
  }

  Future<List<PlanRecordData>> loadPlansForDate(DateTime date) async {
    final db = await database.open();
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db.query(
      'plan',
      where: 'user_id = ? AND plan_date >= ? AND plan_date < ?',
      whereArgs: [
        kLocalUserId,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
      orderBy: 'plan_date ASC, type ASC',
    );
    return rows.map(PlanRecordData.fromRow).toList();
  }

  Future<int> addPlan({
    required DateTime date,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    if (!const {'meal', 'exercise', 'measurement'}.contains(type)) {
      throw ArgumentError.value(type, 'type', '不支持的计划类型');
    }
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final planDate = DateTime(date.year, date.month, date.day);
    final id = await db.insert('plan', {
      ...PlanRecordData(
        type: type,
        planDate: planDate.millisecondsSinceEpoch,
        payload: payload,
        aiProvider: 'manual',
        aiModel: 'manual-edit',
        createdAt: now,
        updatedAt: now,
        version: 1,
        isDirty: 1,
      ).toRow(),
      'client_id': _uuid.v4(),
    });
    notifyListeners();
    return id;
  }

  Future<void> updatePlan(
    int id, {
    required Map<String, dynamic> payload,
  }) async {
    final db = await database.open();
    final rows = await db.query(
      'plan',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, kLocalUserId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'plan',
      {
        'payload_json': jsonEncode(payload),
        'updated_at': now,
        'version': (_asInt(rows.first['version']) ?? 0) + 1,
        'is_dirty': 1,
      },
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, kLocalUserId],
    );
    notifyListeners();
  }

  Future<void> deletePlan(int id) async {
    final db = await database.open();
    await db.transaction((txn) async {
      await _deleteSyncedRow(
        txn,
        table: 'plan',
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, kLocalUserId],
      );
    });
    notifyListeners();
  }

  Future<List<MealRecordData>> loadMealsForDate(DateTime date) async {
    final db = await database.open();
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db.query(
      'meal_record',
      where: 'user_id = ? AND eaten_at >= ? AND eaten_at < ?',
      whereArgs: [
        kLocalUserId,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
      orderBy: 'eaten_at ASC, id ASC',
    );
    return rows.map(MealRecordData.fromRow).toList();
  }

  Future<List<MealRecordData>> loadMealsBetween(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database.open();
    final rows = await db.query(
      'meal_record',
      where: 'user_id = ? AND eaten_at >= ? AND eaten_at < ?',
      whereArgs: [
        kLocalUserId,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
      orderBy: 'eaten_at DESC, id DESC',
    );
    return rows.map(MealRecordData.fromRow).toList();
  }

  Future<MealRecordData?> loadMealRecord(int id) async {
    final db = await database.open();
    final rows = await db.query(
      'meal_record',
      where: 'user_id = ? AND id = ?',
      whereArgs: [kLocalUserId, id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MealRecordData.fromRow(rows.first);
  }

  Future<int> saveMealRecord(MealRecordData meal) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = meal.copyWith(updatedAt: now);
    final isNew = next.id == null;
    int id;
    if (isNew) {
      id = await db.insert('meal_record', next.toRow());
    } else {
      id = next.id!;
      await db.update(
        'meal_record',
        next.toRow()..remove('id'),
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, kLocalUserId],
      );
    }
    if (isNew) {
      await addClockRecord(
        type: 'meal',
        note:
            '${next.mealLabel} ${next.name} ${next.totalCalories.round()} kcal',
        value: next.totalCalories.round(),
        unit: 'kcal',
        detail: next.mealLabel,
        clockAt: next.eatenTime,
      );
    }
    notifyListeners();
    return id;
  }

  Future<void> deleteMealRecord(MealRecordData meal) async {
    if (meal.id == null) return;
    final db = await database.open();
    await db.transaction((txn) async {
      await txn.delete(
        'meal_record',
        where: 'id = ? AND user_id = ?',
        whereArgs: [meal.id, kLocalUserId],
      );
      await txn.delete(
        'clock_record',
        where: 'user_id = ? AND type = ? AND clock_at = ?',
        whereArgs: [kLocalUserId, 'meal', meal.eatenAt],
      );
    });
    notifyListeners();
  }

  Future<List<MealRecipeData>> loadMealRecipes() async {
    final db = await database.open();
    final rows = await db.query(
      'meal_recipe',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
      orderBy: 'is_favorite DESC, updated_at DESC',
    );
    return rows.map(MealRecipeData.fromRow).toList();
  }

  Future<int> saveMealRecipe(MealRecipeData recipe) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = recipe.copyWith(updatedAt: now);
    if (next.id == null) {
      final id = await db.insert('meal_recipe', next.toRow());
      notifyListeners();
      return id;
    }
    await db.update(
      'meal_recipe',
      next.toRow()..remove('id'),
      where: 'id = ? AND user_id = ?',
      whereArgs: [next.id, kLocalUserId],
    );
    notifyListeners();
    return next.id!;
  }

  Future<void> deleteMealRecipe(int id) async {
    final db = await database.open();
    await db.delete(
      'meal_recipe',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, kLocalUserId],
    );
    notifyListeners();
  }

  Future<void> applyPersonalizedMenu({
    required List<dynamic> days,
    required String provider,
  }) async {
    final db = await database.open();
    final today = DateTime.now();
    final todayMs = DateTime(
      today.year,
      today.month,
      today.day,
    ).millisecondsSinceEpoch;
    final createdAt = today.millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete(
        'plan',
        where: 'user_id = ? AND type = ? AND plan_date >= ?',
        whereArgs: [kLocalUserId, 'meal', todayMs],
      );
      for (final rawDay in days) {
        if (rawDay is! Map) continue;
        final date = DateTime.tryParse('${rawDay['date']}');
        final rawMeals = rawDay['meals'];
        if (date == null || rawMeals is! Map) continue;
        final payload = <String, dynamic>{};
        for (final type in ['breakfast', 'lunch', 'dinner', 'snack']) {
          final rawMeal = rawMeals[type];
          if (rawMeal is! Map) continue;
          final name = '${rawMeal['name'] ?? ''}'.trim();
          if (name.isEmpty) continue;
          final ingredients = rawMeal['ingredients'] is List
              ? (rawMeal['ingredients'] as List).map((item) => '$item').toList()
              : <String>[];
          payload[type] = [
            name,
            ...ingredients,
          ];
        }
        payload['summary'] = '个性化菜单，可随时换菜';
        payload['targetCalories'] = _sumMenuCalories(rawMeals);
        await txn.insert(
          'plan',
          PlanRecordData(
            type: 'meal',
            planDate: DateTime(
              date.year,
              date.month,
              date.day,
            ).millisecondsSinceEpoch,
            payload: payload,
            aiProvider: provider,
            aiModel: 'personalized-menu-v1',
            createdAt: createdAt,
            updatedAt: createdAt,
          ).toRow(),
        );
      }
    });
    notifyListeners();
  }

  double _sumMenuCalories(Map<dynamic, dynamic> meals) {
    return meals.values.fold<double>(0, (sum, rawMeal) {
      if (rawMeal is! Map) return sum;
      return sum + ((rawMeal['calories'] as num?)?.toDouble() ?? 0);
    });
  }

  Future<void> ensureStarterMealRecipes() async {
    final db = await database.open();
    if (await db.count(
          'meal_recipe',
          where: 'user_id = ?',
          whereArgs: [kLocalUserId],
        ) >
        0) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final recipes = <MealRecipeData>[
      MealRecipeData(
        clientId: 'starter-tomato-egg',
        name: '番茄鸡蛋杂粮饭',
        category: '主食',
        durationMinutes: 25,
        difficulty: '简单',
        ingredients: const ['番茄 1 个', '鸡蛋 2 个', '杂粮饭 1 碗', '青菜 100 克'],
        steps: const ['番茄切块，鸡蛋打散。', '少油炒鸡蛋后盛出。', '炒软番茄，放回鸡蛋，搭配杂粮饭和青菜。'],
        calories: 520,
        proteinG: 24,
        carbsG: 68,
        fatG: 16,
        isFavorite: false,
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      MealRecipeData(
        clientId: 'starter-steamed-fish',
        name: '清蒸鱼配时蔬',
        category: '水产',
        durationMinutes: 30,
        difficulty: '简单',
        ingredients: const ['鱼柳 180 克', '西兰花 150 克', '姜丝适量', '生抽少量'],
        steps: const ['鱼柳铺姜丝，蒸至熟透。', '西兰花焯熟。', '用少量生抽调味后装盘。'],
        calories: 360,
        proteinG: 42,
        carbsG: 18,
        fatG: 12,
        isFavorite: false,
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      MealRecipeData(
        clientId: 'starter-oat-breakfast',
        name: '牛奶燕麦鸡蛋早餐',
        category: '早餐',
        durationMinutes: 12,
        difficulty: '容易',
        ingredients: const ['燕麦 40 克', '牛奶 250 毫升', '鸡蛋 1 个', '蓝莓 50 克'],
        steps: const ['燕麦加入牛奶煮至浓稠。', '鸡蛋煮熟。', '燕麦碗加入蓝莓后一起食用。'],
        calories: 410,
        proteinG: 21,
        carbsG: 52,
        fatG: 13,
        isFavorite: false,
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      MealRecipeData(
        clientId: 'starter-tofu-soup',
        name: '菌菇豆腐汤',
        category: '汤粥',
        durationMinutes: 20,
        difficulty: '容易',
        ingredients: const ['嫩豆腐 200 克', '菌菇 150 克', '青菜 100 克', '盐少量'],
        steps: const ['菌菇洗净后煮开。', '加入豆腐小火煮 8 分钟。', '放入青菜和少量盐即可。'],
        calories: 260,
        proteinG: 20,
        carbsG: 20,
        fatG: 11,
        isFavorite: false,
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    await db.transaction((txn) async {
      for (final recipe in recipes) {
        await txn.insert('meal_recipe', recipe.toRow());
      }
    });
    notifyListeners();
  }

  Future<Map<String, dynamic>> loadMealSettings() async {
    final db = await database.open();
    final rows = await db.query(
      'meal_settings',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
      limit: 1,
    );
    if (rows.isEmpty) return const {};
    return decodeJson(rows.first['payload_json'] as String? ?? '{}');
  }

  Future<void> saveMealSettings(Map<String, dynamic> settings) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'meal_settings',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
      limit: 1,
    );
    final values = <String, Object?>{
      'user_id': kLocalUserId,
      'payload_json': jsonEncode(settings),
      'updated_at': now,
    };
    if (rows.isEmpty) {
      await db.insert('meal_settings', values);
    } else {
      await db.update(
        'meal_settings',
        values,
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
      );
    }
    notifyListeners();
  }

  // 提取风险评估逻辑，供 generateWeeklyPlan 和 recalculateRisk 共用
  // 参考标准：血压 ACC/AHA 2017 | 血糖 ADA 2024 | 血脂 ACC/AHA 2018
  //           BMI 中国标准 WST428-2013 | 体脂 ACSM | 腰围 IDF亚洲2006
  //           血氧 WHO | 睡眠 NSF/AASM 2015 | 步数 WHO 2022
  Future<_RiskResult> _assessRisk(UserProfileData profile) async {
    final results = await Future.wait([
      loadIndicators(limit: 1, type: 'bp'),
      loadIndicators(limit: 1, type: 'glucose'),
      loadIndicators(limit: 1, type: 'lipid'),
      loadIndicators(limit: 1, type: 'body_fat'),
      loadIndicators(limit: 1, type: 'waist'),
      loadIndicators(limit: 1, type: 'spo2'),
      loadIndicators(limit: 1, type: 'sleep'),
      loadIndicators(limit: 1, type: 'steps'),
      loadIndicators(limit: 1, type: 'heart_rate'),
    ]);

    // ── 血压（ACC/AHA 2017） ────────────────────────────────────
    final latestBp = results[0].firstOrNull;
    final systolic = (latestBp?.payload['systolic'] as num?)?.toInt() ?? 0;
    final diastolic = (latestBp?.payload['diastolic'] as num?)?.toInt() ?? 0;
    final crisisBp = systolic >= 180 || diastolic >= 120;
    final highBp = !crisisBp && (systolic >= 140 || diastolic >= 90); // Stage 2
    final borderlineBp =
        !highBp && !crisisBp && (systolic >= 130 || diastolic >= 80); // Stage 1

    // ── 血糖（ADA 2024，区分空腹/餐后） ─────────────────────────
    final latestGlucose = results[1].firstOrNull;
    final glucoseMmol =
        (latestGlucose?.payload['glucoseMmol'] as num?)?.toDouble() ?? 0;
    final mealType = latestGlucose?.payload['mealType'] as String? ?? 'fasting';
    final bool highGlucose, borderlineGlucose;
    if (mealType == 'postmeal') {
      highGlucose = glucoseMmol >= 11.1;
      borderlineGlucose = !highGlucose && glucoseMmol >= 7.8 && glucoseMmol > 0;
    } else {
      highGlucose = glucoseMmol >= 7.0;
      borderlineGlucose = !highGlucose && glucoseMmol >= 5.6 && glucoseMmol > 0;
    }

    // ── 血脂（ACC/AHA 2018 / NCEP ATP III） ────────────────────
    final latestLipid = results[2].firstOrNull;
    final tc = (latestLipid?.payload['tc'] as num?)?.toDouble() ?? 0;
    final ldl = (latestLipid?.payload['ldl'] as num?)?.toDouble() ?? 0;
    final hdl = (latestLipid?.payload['hdl'] as num?)?.toDouble() ?? 0;
    final tg = (latestLipid?.payload['tg'] as num?)?.toDouble() ?? 0;
    final highLipid = tc >= 6.22 || ldl >= 4.14;
    final borderlineLipid =
        !highLipid && ((tc >= 5.18 && tc > 0) || (ldl >= 3.37 && ldl > 0));
    final isMale = profile.gender == 'male';
    final lowHdl =
        hdl > 0 && ((isMale && hdl < 1.04) || (!isMale && hdl < 1.30));
    final highTg = tg >= 2.26 && tg > 0;

    // ── BMI（中国标准 WST 428-2013） ────────────────────────────
    final bmi = profile.bmi;
    final obese = bmi >= 28;
    final overweight = !obese && bmi >= 24;
    final underweight = bmi > 0 && bmi < 18.5;

    // ── 体脂率（ACSM，按性别） ───────────────────────────────────
    final latestBodyFat = results[3].firstOrNull;
    final bodyFatPct =
        (latestBodyFat?.payload['bodyFatPct'] as num?)?.toDouble() ?? 0;
    final highBodyFat = bodyFatPct > 0 &&
        ((isMale && bodyFatPct >= 25) || (!isMale && bodyFatPct >= 32));

    // ── 腰围（IDF 亚洲标准 2006） ────────────────────────────────
    final latestWaist = results[4].firstOrNull;
    final waistCm = (latestWaist?.payload['waistCm'] as num?)?.toDouble() ?? 0;
    final highWaist = waistCm > 0 &&
        ((isMale && waistCm >= 90) || (!isMale && waistCm >= 80));

    // ── 血氧（WHO） ──────────────────────────────────────────────
    final latestSpo2 = results[5].firstOrNull;
    final spo2 = (latestSpo2?.payload['spo2Pct'] as num?)?.toInt() ?? 0;
    final dangerSpo2 = spo2 > 0 && spo2 < 90;
    final lowSpo2 = !dangerSpo2 && spo2 > 0 && spo2 < 95;

    // ── 睡眠（NSF/AASM 2015） ────────────────────────────────────
    final latestSleep = results[6].firstOrNull;
    final sleepHours =
        (latestSleep?.payload['sleepHours'] as num?)?.toDouble() ?? 0;
    final shortSleep = sleepHours > 0 && sleepHours < 6;
    final borderlineSleep = !shortSleep && sleepHours > 0 && sleepHours < 7;

    // ── 步数（WHO 2022） ─────────────────────────────────────────
    final latestSteps = results[7].firstOrNull;
    final steps = (latestSteps?.payload['steps'] as num?)?.toInt() ?? 0;
    final lowSteps = steps > 0 && steps < 5000;
    final borderlineSteps = !lowSteps && steps > 0 && steps < 7500;

    // ── 心率 ──────────────────────────────────────────────────────
    final latestHr = results[8].firstOrNull;
    final hrBpm = (latestHr?.payload['bpm'] as num?)?.toInt() ?? 0;
    final highHr = hrBpm >= 100 && hrBpm > 0;

    // ── 风险列表 ──────────────────────────────────────────────────
    final risks = <String>[];
    if (crisisBp) {
      risks.add('高血压危象（收缩压 ≥ 180 或舒张压 ≥ 120 mmHg，建议立即就医）');
    }
    if (highBp) {
      risks.add('高血压 Stage 2（收缩压 ≥ 140 或舒张压 ≥ 90 mmHg，ACC/AHA 2017）');
    }
    if (borderlineBp) {
      risks.add('血压偏高 Stage 1（收缩压 130-139 或舒张压 80-89 mmHg，建议生活方式干预）');
    }
    if (highGlucose) {
      risks.add(
        mealType == 'postmeal'
            ? '餐后血糖达糖尿病标准（≥ 11.1 mmol/L，ADA 2024，建议就医）'
            : '空腹血糖达糖尿病标准（≥ 7.0 mmol/L，ADA 2024，建议就医）',
      );
    }
    if (borderlineGlucose) {
      risks.add(
        mealType == 'postmeal'
            ? '餐后血糖偏高（7.8-11.0 mmol/L，糖耐量异常 IGT）'
            : '空腹血糖处于糖尿病前期（5.6-6.9 mmol/L，ADA 标准）',
      );
    }
    if (highLipid) {
      risks.add('血脂明显偏高（TC ≥ 6.22 或 LDL ≥ 4.14 mmol/L，ACC/AHA 高危阈值）');
    }
    if (borderlineLipid) {
      risks.add('血脂处于边界高值（TC 5.18-6.21 或 LDL 3.37-4.13 mmol/L）');
    }
    if (lowHdl) {
      risks.add(
        'HDL 胆固醇偏低（${isMale ? "男 < 1.04" : "女 < 1.30"} mmol/L，心血管保护不足）',
      );
    }
    if (highTg) {
      risks.add('甘油三酯偏高（≥ 2.26 mmol/L，建议减少精制糖和饮酒）');
    }
    if (obese) {
      risks.add('BMI 肥胖（${bmi.toStringAsFixed(1)}，≥ 28，中国标准 WST 428-2013）');
    }
    if (overweight) {
      risks.add('BMI 超重（${bmi.toStringAsFixed(1)}，24.0-27.9，建议适度减重）');
    }
    if (underweight) {
      risks.add('BMI 偏低（${bmi.toStringAsFixed(1)}，< 18.5，建议增加营养）');
    }
    if (highBodyFat) {
      risks.add(
        '体脂率偏高（${bodyFatPct.toStringAsFixed(1)}%，${isMale ? "男 ≥ 25%" : "女 ≥ 32%"}，ACSM 标准）',
      );
    }
    if (highWaist) {
      risks.add(
        '腰围超标（${waistCm.toStringAsFixed(1)} cm，${isMale ? "男 ≥ 90 cm" : "女 ≥ 80 cm"}，IDF 亚洲标准）',
      );
    }
    if (dangerSpo2) {
      risks.add('血氧饱和度危险偏低（$spo2%，< 90%，建议立即就医）');
    }
    if (lowSpo2) {
      risks.add('血氧饱和度偏低（$spo2%，正常 ≥ 95%，WHO 标准）');
    }
    if (shortSleep) {
      risks.add(
        '睡眠严重不足（${sleepHours.toStringAsFixed(1)} h < 6 h，成人建议 7-9 h，NSF 标准）',
      );
    }
    if (borderlineSleep) {
      risks.add('睡眠略显不足（${sleepHours.toStringAsFixed(1)} h，建议达到 7-9 h）');
    }
    if (lowSteps) {
      risks.add('日步数不足（$steps 步，建议每日 ≥ 7500 步，WHO 2022）');
    }
    if (borderlineSteps) {
      risks.add('日步数偏低（$steps 步，建议每日 ≥ 7500 步）');
    }
    if (highHr) {
      risks.add('静息心率偏高（$hrBpm bpm，正常范围 60-100 bpm）');
    }

    // ── 热量目标（Mifflin-St Jeor BMR） ─────────────────────────
    final age = profile.age > 0 ? profile.age : 35;
    final weight = profile.weightKg > 0 ? profile.weightKg : 70;
    final height = profile.heightCm > 0 ? profile.heightCm : 170;
    final bmr = isMale
        ? (10 * weight + 6.25 * height - 5 * age + 5).toInt()
        : (10 * weight + 6.25 * height - 5 * age - 161).toInt();

    final actMultiplier = switch (profile.exerciseBase) {
      'none' => 1.2,
      'light' => 1.375,
      'moderate' => 1.55,
      _ => 1.2,
    };
    final tdee = (bmr * actMultiplier).toInt();
    final targetKcal = switch (profile.goal) {
      'fat_loss' => (tdee - 400).clamp(1200, 3000),
      'glucose_control' => (tdee - 200).clamp(1200, 3000),
      'bp_control' => (tdee - 200).clamp(1200, 3000),
      _ => tdee.clamp(1200, 3000),
    };

    final saltNote = (highBp || borderlineBp || crisisBp)
        ? '低盐（全天钠 < 1500 mg，DASH 饮食）'
        : '少盐少油';
    final carbNote =
        (highGlucose || borderlineGlucose) ? '优先低GI食物，均匀分配三餐碳水' : '';
    final fatNote = (highLipid || borderlineLipid || lowHdl || highTg)
        ? '减少饱和脂肪，增加不饱和脂肪（深海鱼、坚果）'
        : '';
    final dietParts = [
      saltNote,
      if (carbNote.isNotEmpty) carbNote,
      if (fatNote.isNotEmpty) fatNote,
    ];
    final dietNote = dietParts.join('；');

    final goalNote = switch (profile.goal) {
      'fat_loss' => '目标减脂：高蛋白（体重×1.5 g/kg）、减少精制碳水',
      'glucose_control' => '目标控糖：低GI饮食、均匀分配三餐碳水摄入',
      'bp_control' => '目标控压：DASH 饮食原则，多果蔬、低钠',
      _ => '目标保持健康：均衡饮食、维持体重',
    };

    return _RiskResult(
      risks: risks,
      highBp: highBp,
      borderlineBp: borderlineBp,
      crisisBp: crisisBp,
      highGlucose: highGlucose,
      borderlineGlucose: borderlineGlucose,
      highLipid: highLipid,
      borderlineLipid: borderlineLipid,
      lowHdl: lowHdl,
      highTg: highTg,
      obese: obese,
      highBodyFat: highBodyFat,
      highWaist: highWaist,
      lowSpo2: lowSpo2,
      dangerSpo2: dangerSpo2,
      shortSleep: shortSleep,
      lowSteps: lowSteps,
      targetKcal: targetKcal,
      bmr: bmr,
      goalNote: goalNote,
      dietNote: dietNote,
      // 实际数值，用于生成个性化摘要
      systolic: systolic,
      diastolic: diastolic,
      glucoseMmol: glucoseMmol,
      tc: tc,
      ldl: ldl,
      bmi: bmi,
      steps: steps,
      spo2: spo2,
    );
  }

  Future<void> ensurePlanEligible(UserProfileData? profile) async {
    await _eligibleRisk(profile);
  }

  Future<_RiskResult> _eligibleRisk(UserProfileData? profile) async {
    final value = profile ?? await loadProfile();
    if (value == null || !value.isComplete) {
      throw const PlanBlockedException('请先填写有效的性别、出生年份、身高和体重');
    }
    final risk = await _assessRisk(value);
    if (risk.crisisBp || risk.dangerSpo2) {
      throw const PlanBlockedException('检测到紧急健康风险，请立即就医，暂不生成健康或运动计划');
    }
    return risk;
  }

  // 仅重新计算风险，更新 DB 里的 risk 记录，不 notifyListeners（防止循环触发）
  Future<void> recalculateRisk() async {
    final db = await database.open();
    final profile = await loadProfile();
    if (profile == null || !profile.isComplete) {
      throw StateError('请先完善性别、出生年份、身高和体重，再生成基础计划');
    }
    final r = await _assessRisk(profile);
    await _saveRiskPlan(db, r);
    // 不调用 notifyListeners，由调用方决定是否刷新 UI
  }

  Future<void> _saveRiskPlan(AppDatabase db, _RiskResult risk) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final ts = now.millisecondsSinceEpoch;

    await db.delete(
      'plan',
      where: "user_id = ? AND type = 'risk'",
      whereArgs: [kLocalUserId],
    );
    await db.insert(
      'plan',
      PlanRecordData(
        type: 'risk',
        planDate: today.millisecondsSinceEpoch,
        payload: risk.toPayload(),
        aiProvider: 'local',
        aiModel: 'rules-v2',
        createdAt: ts,
        updatedAt: ts,
      ).toRow(),
    );
  }

  Future<void> generateWeeklyPlan({String? goal}) async {
    final db = await database.open();
    final profile = await loadProfile() ?? UserProfileData.empty();
    final r = await _eligibleRisk(profile);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final createdAt = now.millisecondsSinceEpoch;

    final exercisePlans = _buildExerciseTemplates(
      exerciseBase: profile.exerciseBase,
      highBp: r.highBp,
      obese: r.obese,
      goal: goal ?? profile.goal,
    );
    await db.delete(
      'plan',
      where: 'user_id = ? AND type = ? AND plan_date >= ?',
      whereArgs: [
        kLocalUserId,
        'exercise',
        today.millisecondsSinceEpoch,
      ],
    );

    for (var i = 0; i < 7; i++) {
      final date = today.add(Duration(days: i));
      final ms = date.millisecondsSinceEpoch;
      await db.insert(
        'plan',
        PlanRecordData(
          type: 'exercise',
          planDate: ms,
          payload: exercisePlans[i],
          aiProvider: 'local',
          aiModel: 'rules-v2',
          createdAt: createdAt,
          updatedAt: createdAt,
        ).toRow(),
        replace: true,
      );
      final measurements = await db.query(
        'plan',
        where: 'user_id = ? AND type = ? AND plan_date = ?',
        whereArgs: [kLocalUserId, 'measurement', ms],
        limit: 1,
      );
      if (measurements.isEmpty) {
        await db.insert(
          'plan',
          PlanRecordData(
            type: 'measurement',
            planDate: ms,
            payload: const {
              'summary': '晨起体重',
              'items': ['起床后、早餐前记录体重'],
            },
            aiProvider: 'local',
            aiModel: 'measurement-default-v1',
            createdAt: createdAt,
            updatedAt: createdAt,
          ).toRow(),
        );
      }
    }

    await db.insert(
      'plan',
      PlanRecordData(
        type: 'risk',
        planDate: today.millisecondsSinceEpoch,
        payload: r.toPayload(),
        aiProvider: 'local',
        aiModel: 'rules-v2',
        createdAt: createdAt,
        updatedAt: createdAt,
      ).toRow(),
      replace: true,
    );

    final reminders = await loadReminders();
    if (reminders.isEmpty) {
      await _insertDefaultReminders(db, createdAt);
      if (r.highBp || r.borderlineBp) {
        await db.insert(
          'reminder',
          ReminderData(
            type: 'bp',
            remindAt: DateTime(
              now.year,
              now.month,
              now.day,
              19,
              0,
            ).millisecondsSinceEpoch,
            payload: {'note': '晚间血压监测（安静休息5分钟后测量）'},
            channel: 'local',
            status: 'pending',
            createdAt: createdAt,
            updatedAt: createdAt,
          ).toRow(),
        );
      }
      if (r.highGlucose || r.borderlineGlucose) {
        await db.insert(
          'reminder',
          ReminderData(
            type: 'glucose',
            remindAt: DateTime(
              now.year,
              now.month,
              now.day,
              9,
              30,
            ).millisecondsSinceEpoch,
            payload: {'note': '餐后2小时血糖监测'},
            channel: 'local',
            status: 'pending',
            createdAt: createdAt,
            updatedAt: createdAt,
          ).toRow(),
        );
      }
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> buildLocalWeeklyPlanPreview({
    required String goal,
    String goalDetail = '',
    DateTime? targetDate,
  }) async {
    final profile = await loadProfile() ?? UserProfileData.empty();
    final risk = await _eligibleRisk(profile);
    final exercisePlans = _buildExerciseTemplates(
      exerciseBase: profile.exerciseBase,
      highBp: risk.highBp,
      obese: risk.obese,
      goal: goal,
    );
    const weekDays = ['第1天', '第2天', '第3天', '第4天', '第5天', '第6天', '第7天'];
    final measurements = switch (goal) {
      'bp_control' => ['固定时段测量血压并记录'],
      'glucose_control' => ['按既有医嘱记录空腹或餐后血糖'],
      'sleep_better' => ['记录入睡时间、起床时间和睡眠感受'],
      'fat_loss' => ['晨起、早餐前记录体重', '每周固定一天记录腰围'],
      _ => ['晨起、早餐前记录体重', '运动后记录主观疲劳程度'],
    };
    final habit = switch (goal) {
      'sleep_better' => '保持固定起床时间，睡前减少屏幕刺激',
      'quit_smoking' => '记录吸烟冲动出现的时间、场景和应对方式',
      'bp_control' => '久坐一小时后起身活动，并练习缓慢呼吸',
      'glucose_control' => '避免长时间静坐，按计划完成轻量活动',
      'fat_loss' => '记录每日步数和计划完成度',
      'muscle_gain' => '训练后完成放松，并保证充分恢复',
      _ => '在固定时间运动，并记录当天完成感受',
    };
    final detail = goalDetail.trim();
    final targetText = targetDate == null
        ? ''
        : '目标日期：${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

    return {
      'summary': [
        '根据档案生成的本地 7 天专属计划',
        if (detail.isNotEmpty) '期望状态：$detail',
        if (targetText.isNotEmpty) targetText,
      ].join('；'),
      'days': [
        for (var i = 0; i < exercisePlans.length; i++)
          {
            'weekDay': weekDays[i],
            'exercise': {
              ...exercisePlans[i],
              'title': exercisePlans[i]['type'],
              'totalMinutes': exercisePlans[i]['durationMinutes'],
            },
            'measurements': measurements,
            'habits': [
              habit,
              if (detail.isNotEmpty) '围绕补充目标复盘：$detail',
              if (targetText.isNotEmpty && i == 6) '检查阶段进度并调整下一周安排',
            ],
            'reminders': ['运动前确认身体状态，出现不适立即停止', '睡前记录当天完成情况'],
          },
      ],
    };
  }

  Future<void> applyAiPlan({
    required Map<String, dynamic> plan,
    required String provider,
    bool createReminders = true,
    bool replaceExisting = true,
  }) async {
    final rawDays = plan['days'];
    final days = rawDays is List
        ? rawDays
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    if (days.isEmpty) {
      throw const FormatException('AI 方案缺少 7 天计划明细');
    }

    final db = await database.open();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final timestamp = now.millisecondsSinceEpoch;

    await db.transaction((txn) async {
      if (replaceExisting) {
        await txn.delete(
          'plan',
          where: 'user_id = ? AND type = ? AND plan_date >= ?',
          whereArgs: [
            kLocalUserId,
            'exercise',
            today.millisecondsSinceEpoch,
          ],
        );
        await _deleteSyncedRow(
          txn,
          table: 'reminder',
          where: 'user_id = ? AND channel = ?',
          whereArgs: [kLocalUserId, 'ai-plan'],
        );
      }

      for (var i = 0; i < days.length && i < 7; i++) {
        final day = days[i];
        final date = today.add(Duration(days: i));
        final planDate = date.millisecondsSinceEpoch;
        final exercise = _aiMap(day['exercise']);
        final measurements = _aiStringList(day['measurements']);
        final habits = _aiStringList(day['habits']);
        final reminders = _aiStringList(day['reminders']);

        await txn.insert(
          'plan',
          PlanRecordData(
            type: 'exercise',
            planDate: planDate,
            payload: _aiExercisePayload(exercise),
            aiProvider: provider,
            aiModel: 'ai-plan-json',
            createdAt: timestamp,
            updatedAt: timestamp,
            version: 1,
            isDirty: 1,
          ).toRow(),
          replace: true,
        );

        final existingMeasurements = await txn.query(
          'plan',
          where: 'user_id = ? AND type = ? AND plan_date = ?',
          whereArgs: [kLocalUserId, 'measurement', planDate],
          limit: 1,
        );
        final measurementItems = [
          if (measurements.isEmpty) '晨起、早餐前记录体重' else ...measurements,
          for (final habit in habits) '生活习惯 · $habit',
        ];
        if (existingMeasurements.isNotEmpty && !replaceExisting) {
          final existing = PlanRecordData.fromRow(existingMeasurements.first);
          final mergedItems = <String>{
            ..._aiStringList(existing.payload['items']),
            ...measurementItems,
          }.toList();
          await txn.update(
            'plan',
            {
              'payload_json': jsonEncode({
                'summary': '每日测量与生活习惯',
                'items': mergedItems,
              }),
              'updated_at': timestamp,
              'version': existing.version + 1,
              'is_dirty': 1,
            },
            where: 'id = ? AND user_id = ?',
            whereArgs: [existing.id, kLocalUserId],
          );
        } else {
          if (existingMeasurements.isNotEmpty) {
            await txn.delete(
              'plan',
              where: 'user_id = ? AND type = ? AND plan_date = ?',
              whereArgs: [kLocalUserId, 'measurement', planDate],
            );
          }
          await txn.insert(
            'plan',
            PlanRecordData(
              type: 'measurement',
              planDate: planDate,
              payload: {
                'summary': '每日测量与生活习惯',
                'items': measurementItems,
              },
              aiProvider: 'local',
              aiModel: 'measurement-default-v1',
              createdAt: timestamp,
              updatedAt: timestamp,
              version: 1,
              isDirty: 1,
            ).toRow(),
          );
        }

        if (createReminders) {
          await _insertAiPlanReminders(
            txn,
            date: date,
            exercise: exercise,
            reminders: reminders,
            timestamp: timestamp,
            dayIndex: i + 1,
          );
        }
      }
    });

    notifyListeners();
  }

  // ignore: unused_element
  Map<String, dynamic> _aiMealPayload(
    Map<String, dynamic> diet, {
    required String keyFocus,
    required int? targetCalories,
  }) {
    final breakfast = _aiStringList(diet['breakfast']);
    final lunch = _aiStringList(diet['lunch']);
    final dinner = _aiStringList(diet['dinner']);
    final snack = _aiStringList(diet['snack']);
    final notes = _aiText(diet['notes']);

    return {
      'summary': notes.isNotEmpty
          ? notes
          : [
              if (targetCalories != null) '$targetCalories kcal',
              if (keyFocus.isNotEmpty) keyFocus,
              if (breakfast.isNotEmpty) breakfast.first,
            ].join('，'),
      if (keyFocus.isNotEmpty) 'goalNote': keyFocus,
      if (targetCalories != null) 'targetCalories': targetCalories,
      'breakfast': breakfast,
      'lunch': lunch,
      'dinner': dinner,
      'snack': snack,
    };
  }

  Map<String, dynamic> _aiExercisePayload(Map<String, dynamic> exercise) {
    final type = _aiText(exercise['title']);
    final goal = _aiText(exercise['goal']);
    final duration = _aiNumber(exercise['totalMinutes'])?.round();
    final intensity = _aiText(exercise['intensity']);
    final location = _aiText(exercise['location']);
    final equipment = _aiStringList(exercise['equipment']);
    final warmup = _aiMapList(exercise['warmup']);
    final main = _aiMapList(exercise['main']);
    final cooldown = _aiMapList(exercise['cooldown']);
    final safetyNotes = _aiStringList(exercise['safetyNotes']);
    final alternative = _aiMap(exercise['alternative']);
    final items = <String>[
      for (final step in warmup) _exerciseStepText('热身', step),
      for (final step in main) _exerciseStepText('主训练', step),
      for (final step in cooldown) _exerciseStepText('放松', step),
      for (final note in safetyNotes) '注意 · $note',
      if (_aiText(alternative['name']).isNotEmpty)
        '替代 · ${_aiText(alternative['condition'])}：${_aiText(alternative['name'])}，${_aiText(alternative['instruction'])}',
    ].where((item) => item.trim().isNotEmpty).toList();
    final summaryParts = [
      if (type.isNotEmpty) type,
      if (duration != null && duration > 0) '$duration 分钟',
      if (intensity.isNotEmpty) intensity,
    ];

    return {
      'summary':
          summaryParts.isNotEmpty ? summaryParts.join(' · ') : '按 AI 建议完成今日运动',
      if (type.isNotEmpty) 'type': type,
      if (goal.isNotEmpty) 'goal': goal,
      if (duration != null) 'duration': duration,
      if (duration != null) 'durationMinutes': duration,
      if (intensity.isNotEmpty) 'intensity': intensity,
      if (location.isNotEmpty) 'location': location,
      if (equipment.isNotEmpty) 'equipment': equipment,
      'warmup': warmup,
      'main': main,
      'cooldown': cooldown,
      'safetyNotes': safetyNotes,
      if (alternative.isNotEmpty) 'alternative': alternative,
      'items': items,
    };
  }

  String _exerciseStepText(String phase, Map<String, dynamic> step) {
    final name = _aiText(step['name']);
    final sets = _aiNumber(step['sets'])?.round();
    final reps = _aiText(step['reps']);
    final minutes = _aiNumber(step['durationMinutes'])?.round();
    final rest = _aiNumber(step['restSeconds'])?.round();
    final instruction = _aiText(step['instruction']);
    return [
      '$phase · $name',
      if (sets != null && sets > 0) '$sets组${reps.isEmpty ? '' : ' × $reps'}',
      if (minutes != null && minutes > 0) '$minutes分钟',
      if (rest != null && rest > 0) '休息$rest秒',
      if (instruction.isNotEmpty) instruction,
    ].join(' · ');
  }

  // ignore: unused_element
  Map<String, dynamic> _aiMeasurementPayload(List<String> reminders) {
    final items =
        reminders.isEmpty ? const ['晨起空腹体重', '按需记录血压、血糖或今日不适'] : reminders;
    return {'summary': '今日 ${items.length} 项提醒', 'items': items};
  }

  Future<void> _insertAiPlanReminders(
    AppDatabase txn, {
    required DateTime date,
    required Map<String, dynamic> exercise,
    required List<String> reminders,
    required int timestamp,
    required int dayIndex,
  }) async {
    final tasks = <({String type, DateTime at, String note})>[];
    final exerciseSummary =
        _aiExercisePayload(exercise)['summary'] as String? ?? '';

    if (exerciseSummary.isNotEmpty) {
      tasks.add((
        type: 'exercise',
        at: DateTime(date.year, date.month, date.day, 19, 30),
        note: '第 $dayIndex 天运动：$exerciseSummary',
      ));
    }
    for (var i = 0; i < reminders.length; i++) {
      tasks.add((
        type: 'exercise',
        at: DateTime(date.year, date.month, date.day, 19, 20 + i * 5),
        note: reminders[i],
      ));
    }
    final seen = <String>{};
    for (final task in tasks) {
      final key = '${task.type}-${task.at.millisecondsSinceEpoch}-${task.note}';
      if (!seen.add(key)) continue;
      await txn.insert(
        'reminder',
        ReminderData(
          type: task.type,
          remindAt: task.at.millisecondsSinceEpoch,
          payload: {'note': task.note, 'source': 'ai-plan'},
          channel: 'ai-plan',
          status: 'pending',
          createdAt: timestamp,
          updatedAt: timestamp,
          version: 1,
          isDirty: 1,
        ).toRow(),
      );
    }
  }

  Map<String, dynamic> _aiMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((key, value) => MapEntry('$key', value));
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _aiMapList(Object? raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.whereType<Map>().map(_aiMap).toList();
  }

  List<String> _aiStringList(Object? raw) {
    if (raw is List) {
      return raw.map(_aiText).where((item) => item.isNotEmpty).toList();
    }
    final text = _aiText(raw);
    if (text.isEmpty) return <String>[];
    return [text];
  }

  String _aiText(Object? raw) {
    if (raw == null) return '';
    return raw.toString().trim();
  }

  num? _aiNumber(Object? raw) {
    if (raw is num) return raw;
    if (raw == null) return null;
    return num.tryParse(raw.toString().trim());
  }

  Future<List<ClockRecordData>> loadClockRecords({int limit = 40}) async {
    final db = await database.open();
    final rows = await db.query(
      'clock_record',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
      orderBy: 'clock_at DESC',
      limit: limit,
    );
    return rows.map(ClockRecordData.fromRow).toList();
  }

  Future<int> addClockRecord({
    required String type,
    String status = 'done',
    String note = '',
    num? value,
    String unit = '',
    String detail = '',
    DateTime? clockAt,
  }) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert(
      'clock_record',
      ClockRecordData(
        type: type,
        status: status,
        clockAt: (clockAt ?? DateTime.now()).millisecondsSinceEpoch,
        note: note,
        photoPath: '',
        value: value,
        unit: unit,
        detail: detail,
        createdAt: now,
        updatedAt: now,
      ).toRow(),
    );
    notifyListeners();
    return id;
  }

  Future<void> deleteClockRecord(int id) async {
    final db = await database.open();
    await db.transaction((txn) async {
      await _deleteSyncedRow(
        txn,
        table: 'clock_record',
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, kLocalUserId],
      );
    });
    notifyListeners();
  }

  Future<void> updateClockRecord(
    ClockRecordData record, {
    required String note,
    num? value,
    String unit = '',
    String detail = '',
  }) async {
    if (record.id == null) return;
    final db = await database.open();
    await db.update(
      'clock_record',
      record.toRow()
        ..remove('id')
        ..['note'] = note
        ..['value'] = value
        ..['unit'] = unit
        ..['detail'] = detail
        ..['updated_at'] = DateTime.now().millisecondsSinceEpoch,
      where: 'id = ? AND user_id = ?',
      whereArgs: [record.id, kLocalUserId],
    );
    notifyListeners();
  }

  Future<List<ReminderData>> loadReminders() async {
    final db = await database.open();
    final rows = await db.query(
      'reminder',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
      orderBy: 'remind_at ASC',
    );
    return rows.map(ReminderData.fromRow).toList();
  }

  Future<int> cleanupDuplicateReminders() async {
    final db = await database.open();
    var deleted = 0;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'reminder',
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
        orderBy: 'updated_at DESC',
      );
      final seen = <String>{};
      for (final row in rows) {
        final reminder = ReminderData.fromRow(row);
        if (!reminder.isEnabled) continue;
        final key = _reminderDefinitionKey(reminder);
        if (seen.add(key)) continue;
        await _queueDelete(txn, 'reminder', row);
        await txn.delete('reminder', where: 'id = ?', whereArgs: [row['id']]);
        deleted++;
      }
    });
    if (deleted > 0) notifyListeners();
    return deleted;
  }

  Future<int> cleanupAiPlanReminders() async {
    final db = await database.open();
    final now = DateTime.now();
    final end = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 7));
    var deleted = 0;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'reminder',
        where: 'user_id = ? AND channel = ?',
        whereArgs: [kLocalUserId, 'ai-plan'],
        orderBy: 'updated_at DESC',
      );
      final seen = <String>{};

      for (final row in rows) {
        final remindAt = _asInt(row['remind_at']) ?? 0;
        final time = DateTime.fromMillisecondsSinceEpoch(remindAt);
        final type = row['type'] as String? ?? '';
        final supported = (type == 'meal' &&
                time.minute == 0 &&
                (time.hour == 8 || time.hour == 12 || time.hour == 18)) ||
            (type == 'exercise' && time.hour == 19 && time.minute == 30);
        final key = '$type-$remindAt';
        if (supported &&
            !time.isBefore(now) &&
            time.isBefore(end) &&
            seen.add(key)) {
          continue;
        }

        await _queueDelete(txn, 'reminder', row);
        await txn.delete('reminder', where: 'id = ?', whereArgs: [row['id']]);
        deleted++;
      }
    });

    if (deleted > 0) notifyListeners();
    return deleted;
  }

  Future<ReminderData> addReminder({
    required String type,
    required TimeOfDayValue time,
    required DateTime date,
    required String scheduleMode,
    required List<int> weekdays,
    String note = '',
    String imageObjectKey = '',
    String imageMimeType = '',
    bool syncAlarm = false,
    Map<String, Object?> payloadExtras = const {},
  }) async {
    final db = await database.open();
    final now = DateTime.now();
    final remindAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final timestamp = now.millisecondsSinceEpoch;
    final payload = <String, dynamic>{
      'note': note,
      'syncAlarm': syncAlarm,
      'scheduleMode': scheduleMode,
      'startDate': DateTime(
        date.year,
        date.month,
        date.day,
      ).millisecondsSinceEpoch,
      'weekdays': scheduleMode == 'weekly'
          ? (weekdays.toSet().toList()..sort())
          : <int>[],
      ...payloadExtras,
    };
    if (imageObjectKey.isNotEmpty) {
      payload['imageObjectKey'] = imageObjectKey;
      payload['imageMimeType'] = imageMimeType;
    }
    final reminder = ReminderData(
      type: type,
      remindAt: remindAt.millisecondsSinceEpoch,
      payload: payload,
      channel: 'local',
      status: 'pending',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final definitionKey = _reminderDefinitionKey(reminder);
    final existing = (await loadReminders()).where(
      (item) => item.isEnabled && _reminderDefinitionKey(item) == definitionKey,
    );
    if (existing.isNotEmpty) return existing.first;
    final id = await db.insert('reminder', reminder.toRow());
    notifyListeners();
    return ReminderData(
      id: id,
      type: reminder.type,
      remindAt: reminder.remindAt,
      payload: reminder.payload,
      channel: reminder.channel,
      status: reminder.status,
      createdAt: reminder.createdAt,
      updatedAt: reminder.updatedAt,
    );
  }

  Future<ReminderData> updateReminder({
    required ReminderData reminder,
    required TimeOfDayValue time,
    required DateTime date,
    required String scheduleMode,
    required List<int> weekdays,
    required String note,
    required String imageObjectKey,
    required String imageMimeType,
    required bool syncAlarm,
    Map<String, Object?> payloadExtras = const {},
  }) async {
    final id = reminder.id;
    if (id == null) throw StateError('提醒记录无效');
    final db = await database.open();
    final now = DateTime.now();
    final remindAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final payload = Map<String, dynamic>.from(reminder.payload)
      ..['note'] = note
      ..['syncAlarm'] = syncAlarm
      ..['scheduleMode'] = scheduleMode
      ..['startDate'] = DateTime(
        date.year,
        date.month,
        date.day,
      ).millisecondsSinceEpoch
      ..['weekdays'] = scheduleMode == 'weekly'
          ? (weekdays.toSet().toList()..sort())
          : <int>[]
      ..addAll(payloadExtras);
    if (imageObjectKey.isEmpty) {
      payload
        ..remove('imageObjectKey')
        ..remove('imageMimeType');
    } else {
      payload['imageObjectKey'] = imageObjectKey;
      payload['imageMimeType'] = imageMimeType;
    }
    final updated = ReminderData(
      id: id,
      userId: reminder.userId,
      type: reminder.type,
      remindAt: remindAt.millisecondsSinceEpoch,
      payload: payload,
      channel: reminder.channel,
      status: reminder.status,
      createdAt: reminder.createdAt,
      updatedAt: now.millisecondsSinceEpoch,
      version: reminder.version + 1,
      isDirty: 1,
    );
    await db.update(
      'reminder',
      updated.toRow(),
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, kLocalUserId],
    );
    notifyListeners();
    return updated;
  }

  Future<ReminderData> setReminderEnabled(
    ReminderData reminder,
    bool enabled,
  ) async {
    final id = reminder.id;
    if (id == null) throw StateError('提醒记录无效');
    final db = await database.open();
    final updated = ReminderData(
      id: id,
      userId: reminder.userId,
      type: reminder.type,
      remindAt: reminder.remindAt,
      payload: reminder.payload,
      channel: reminder.channel,
      status: enabled ? 'pending' : 'paused',
      createdAt: reminder.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      version: reminder.version + 1,
      isDirty: 1,
    );
    await db.update(
      'reminder',
      {
        'status': updated.status,
        'updated_at': updated.updatedAt,
        'version': updated.version,
        'is_dirty': updated.isDirty,
      },
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, kLocalUserId],
    );
    notifyListeners();
    return updated;
  }

  Future<void> deleteReminder(int id) async {
    final db = await database.open();
    await db.transaction((txn) async {
      await _deleteSyncedRow(
        txn,
        table: 'reminder',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    notifyListeners();
  }

  Future<List<ReminderData>> cleanupExpiredOnceReminders(DateTime now) async {
    final db = await database.open();
    final expired = <ReminderData>[];
    await db.transaction((txn) async {
      final rows = await txn.query(
        'reminder',
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
      );
      for (final row in rows) {
        final reminder = ReminderData.fromRow(row);
        final latestTime = reminder.dailyTimes.last;
        final expiresAt = DateTime(
          reminder.remindTime.year,
          reminder.remindTime.month,
          reminder.remindTime.day,
          latestTime.hour,
          latestTime.minute,
        ).add(Duration(minutes: reminder.type == 'medicine' ? 30 : 0));
        if (reminder.isWeekly || expiresAt.isAfter(now)) continue;
        await _deleteSyncedRow(
          txn,
          table: 'reminder',
          where: 'id = ?',
          whereArgs: [reminder.id],
        );
        expired.add(reminder);
      }
    });
    if (expired.isNotEmpty) notifyListeners();
    return expired;
  }

  Future<List<ReminderData>> archiveCompletedMedicationCourses(
    DateTime now,
  ) async {
    final db = await database.open();
    final archived = <ReminderData>[];
    final today = DateTime(now.year, now.month, now.day);
    await db.transaction((txn) async {
      final rows = await txn.query(
        'reminder',
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
      );
      for (final row in rows) {
        final reminder = ReminderData.fromRow(row);
        final courseEnd = reminder.courseEndDate;
        if (reminder.type != 'medicine' ||
            reminder.isArchived ||
            courseEnd == null ||
            !courseEnd.isBefore(today)) {
          continue;
        }
        final payload = Map<String, dynamic>.from(reminder.payload)
          ..['archived'] = true
          ..['archivedAt'] = now.millisecondsSinceEpoch;
        final updated = ReminderData(
          id: reminder.id,
          userId: reminder.userId,
          type: reminder.type,
          remindAt: reminder.remindAt,
          payload: payload,
          channel: reminder.channel,
          status: reminder.status,
          createdAt: reminder.createdAt,
          updatedAt: now.millisecondsSinceEpoch,
          version: reminder.version + 1,
          isDirty: 1,
        );
        await txn.update(
          'reminder',
          updated.toRow(),
          where: 'id = ? AND user_id = ?',
          whereArgs: [reminder.id, kLocalUserId],
        );
        archived.add(updated);
      }
    });
    if (archived.isNotEmpty) notifyListeners();
    return archived;
  }

  Future<ReminderData> recordMedicationAction(
    ReminderData reminder,
    String action, {
    DateTime? scheduledAt,
  }) async {
    final id = reminder.id;
    if (id == null || reminder.type != 'medicine') {
      throw StateError('用药提醒记录无效');
    }
    if (action != 'taken' && action != 'skipped') {
      throw ArgumentError.value(action, 'action', '不支持的用药状态');
    }
    final db = await database.open();
    final now = DateTime.now();
    final occurrence = scheduledAt ?? now;
    final occurrenceKey = _reminderOccurrenceKey(occurrence);
    final rawHistory = reminder.payload['actionHistory'];
    final history = rawHistory is Map
        ? rawHistory.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final previousAction = history[occurrenceKey]?.toString();
    if (previousAction == action) return reminder;
    history[occurrenceKey] = action;
    while (history.length > 120) {
      final oldest = history.keys.toList()..sort();
      history.remove(oldest.first);
    }
    final payload = Map<String, dynamic>.from(reminder.payload)
      ..['lastAction'] = action
      ..['lastActionAt'] = now.millisecondsSinceEpoch
      ..['actionHistory'] = history;
    final remaining = reminder.inventoryRemaining;
    if (remaining != null && previousAction != action) {
      if (action == 'taken') {
        payload['inventoryRemaining'] =
            (remaining - 1).clamp(0, double.infinity);
      } else if (previousAction == 'taken') {
        payload['inventoryRemaining'] = remaining + 1;
      }
    }
    final updated = ReminderData(
      id: id,
      userId: reminder.userId,
      type: reminder.type,
      remindAt: reminder.remindAt,
      payload: payload,
      channel: reminder.channel,
      status: reminder.status,
      createdAt: reminder.createdAt,
      updatedAt: now.millisecondsSinceEpoch,
      version: reminder.version + 1,
      isDirty: 1,
    );
    await db.transaction((txn) async {
      await txn.update(
        'reminder',
        updated.toRow(),
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, kLocalUserId],
      );
      await txn.insert(
        'clock_record',
        ClockRecordData(
          type: 'medicine',
          status: action == 'taken' ? 'done' : 'skip',
          clockAt: now.millisecondsSinceEpoch,
          note:
              '${reminder.displayLabel} · ${action == 'taken' ? '已服' : '已跳过'}',
          photoPath: '',
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ).toRow(),
      );
    });
    notifyListeners();
    return updated;
  }

  Future<ReminderData> acknowledgeReminder(
    ReminderData reminder,
    DateTime scheduledAt,
  ) async {
    final id = reminder.id;
    if (id == null || reminder.type == 'medicine') {
      throw StateError('提醒记录无效');
    }
    final key = _reminderOccurrenceKey(scheduledAt);
    final rawHistory = reminder.payload['ackHistory'];
    final history = rawHistory is Map
        ? rawHistory.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    if (history[key] == true) return reminder;
    history[key] = true;
    while (history.length > 120) {
      final oldest = history.keys.toList()..sort();
      history.remove(oldest.first);
    }
    final now = DateTime.now();
    final updated = ReminderData(
      id: id,
      userId: reminder.userId,
      type: reminder.type,
      remindAt: reminder.remindAt,
      payload: Map<String, dynamic>.from(reminder.payload)
        ..['ackHistory'] = history,
      channel: reminder.channel,
      status: reminder.status,
      createdAt: reminder.createdAt,
      updatedAt: now.millisecondsSinceEpoch,
      version: reminder.version + 1,
      isDirty: 1,
    );
    final db = await database.open();
    await db.transaction((txn) async {
      await txn.update(
        'reminder',
        updated.toRow(),
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, kLocalUserId],
      );
      await txn.insert(
        'clock_record',
        ClockRecordData(
          type: reminder.type,
          status: 'done',
          clockAt: now.millisecondsSinceEpoch,
          note: reminder.displayLabel,
          photoPath: '',
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ).toRow(),
      );
    });
    notifyListeners();
    return updated;
  }

  Future<ReminderData> archiveMedication(ReminderData reminder) async {
    final payload = Map<String, dynamic>.from(reminder.payload)
      ..['archived'] = true
      ..['archivedAt'] = DateTime.now().millisecondsSinceEpoch;
    return updateReminder(
      reminder: reminder,
      time: TimeOfDayValue(
        hour: reminder.remindTime.hour,
        minute: reminder.remindTime.minute,
      ),
      date: reminder.startDate,
      scheduleMode: reminder.isWeekly ? 'weekly' : 'once',
      weekdays: reminder.weekdays,
      note: reminder.payload['note']?.toString() ?? reminder.displayLabel,
      imageObjectKey: reminder.payload['imageObjectKey']?.toString() ?? '',
      imageMimeType: reminder.payload['imageMimeType']?.toString() ?? '',
      syncAlarm: false,
      payloadExtras: payload,
    );
  }

  Future<void> deleteIndicator(int id) async {
    final db = await database.open();
    await db.transaction((txn) async {
      await _deleteSyncedRow(
        txn,
        table: 'health_indicator',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    notifyListeners();
  }

  Future<void> deleteWeightMeasurementAt(DateTime measuredAt) async {
    final db = await database.open();
    final timestamp = measuredAt.millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final type in const ['weight', 'bmi']) {
        await txn.delete(
          'health_indicator',
          where: 'user_id = ? AND type = ? AND measured_at = ?',
          whereArgs: [kLocalUserId, type, timestamp],
        );
      }
    });
    notifyListeners();
  }

  Future<void> updateWeightMeasurementAt(
    DateTime measuredAt,
    double weightKg,
  ) async {
    final db = await database.open();
    final timestamp = measuredAt.millisecondsSinceEpoch;
    await db.update(
      'health_indicator',
      HealthIndicatorEntry(
        clientId: _uuid.v4(),
        type: 'weight',
        payload: {'weightKg': weightKg},
        source: 'manual',
        measuredAt: timestamp,
        createdAt: timestamp,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ).toRow()
        ..remove('id'),
      where: 'user_id = ? AND type = ? AND measured_at = ?',
      whereArgs: [kLocalUserId, 'weight', timestamp],
    );
    final profile = await loadProfile();
    if (profile != null) {
      final updatedProfile = profile.copyWith(weightKg: weightKg);
      await saveProfile(updatedProfile);
      final bmiValue = updatedProfile.bmi;
      if (bmiValue > 0) {
        final rows = await db.query(
          'health_indicator',
          where: 'user_id = ? AND type = ? AND measured_at = ?',
          whereArgs: [kLocalUserId, 'bmi', timestamp],
          limit: 1,
        );
        final existing =
            rows.isEmpty ? null : HealthIndicatorEntry.fromRow(rows.first);
        final bmiEntry = HealthIndicatorEntry(
          clientId: existing?.clientId ?? _uuid.v4(),
          type: 'bmi',
          payload: {
            'bmiValue': double.parse(bmiValue.toStringAsFixed(2)),
          },
          source: 'calculated',
          measuredAt: timestamp,
          createdAt: existing?.createdAt ?? timestamp,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        if (existing == null) {
          await db.insert('health_indicator', bmiEntry.toRow());
        } else {
          await db.update(
            'health_indicator',
            bmiEntry.toRow(),
            where: 'id = ?',
            whereArgs: [existing.id],
          );
        }
      }
    }
    notifyListeners();
  }

  Future<void> addWeightClockRecord(double weightKg) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await addIndicator(
      type: 'weight',
      payload: {'weightKg': weightKg},
      measuredAt: DateTime.fromMillisecondsSinceEpoch(now),
      source: 'manual',
    );
    await addClockRecord(
      type: 'weight',
      status: 'done',
      note: '体重 ${weightKg.toStringAsFixed(1)} kg',
    );
  }

  Future<List<HealthReportRecord>> loadReportRecords({int limit = 50}) async {
    final db = await database.open();
    final rows = await db.query(
      'health_report',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
      orderBy: 'report_time DESC, id DESC',
      limit: limit,
    );
    return rows.map(HealthReportRecord.fromRow).toList();
  }

  Future<List<WeeklyHealthReportData>> loadWeeklyHealthReports({
    int limit = 20,
  }) async {
    final db = await database.open();
    final rows = await db.query(
      'ai_weekly_report',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
      orderBy: 'end_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(WeeklyHealthReportData.fromRow).toList();
  }

  Future<void> saveWeeklyHealthReport({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, dynamic> structured,
    required String provider,
  }) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'ai_weekly_report',
      WeeklyHealthReportData(
        clientId: newClientId(),
        startAt: DateTime(startDate.year, startDate.month, startDate.day)
            .millisecondsSinceEpoch,
        endAt: DateTime(endDate.year, endDate.month, endDate.day)
            .millisecondsSinceEpoch,
        structured: structured,
        provider: provider,
        createdAt: now,
        updatedAt: now,
      ).toRow(),
    );
    notifyListeners();
  }

  Future<void> saveReportRecord({
    required String clientId,
    required String imagePath,
    required DateTime reportTime,
    required String summary,
    required String rawText,
    required Map<String, dynamic> structured,
    required String provider,
  }) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = HealthReportRecord(
      userId: kLocalUserId,
      clientId: clientId,
      imagePath: imagePath,
      reportTime: reportTime.millisecondsSinceEpoch,
      summary: summary,
      rawText: rawText,
      structured: structured,
      provider: provider,
      createdAt: now,
      updatedAt: now,
      version: 1,
      isDirty: 1,
      syncAt: 0,
    );
    await db.insert('health_report', record.toRow(), replace: true);
    notifyListeners();
  }

  Future<void> deleteReportRecord(String clientId) async {
    final db = await database.open();
    await db.transaction((txn) async {
      await _deleteSyncedRow(
        txn,
        table: 'health_report',
        where: 'user_id = ? AND client_id = ?',
        whereArgs: [kLocalUserId, clientId],
      );
    });
    notifyListeners();
  }

  Future<void> _deleteSyncedRow(
    AppDatabase db, {
    required String table,
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final rows = await db.query(table, where: where, whereArgs: whereArgs);
    for (final row in rows) {
      await _queueDelete(db, table, row);
    }
    await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> _queueDelete(
    AppDatabase db,
    String table,
    Map<String, Object?> row,
  ) async {
    final clientId = row['client_id'] as String?;
    if (clientId == null || clientId.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final version = (_asInt(row['version']) ?? 0) + 1;
    await db.insert('sync_queue', {
      'table_name': table,
      'row_id': _asInt(row['id']) ?? 0,
      'op': 'delete',
      'payload_json': jsonEncode({
        'table': table,
        'clientId': clientId,
        'version': version,
        'clientUpdatedAt': now,
      }),
      'retry': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  // 清空本地全部数据（不可逆）
  Future<void> clearAllData() async {
    final db = await database.open();
    for (final table in [
      'health_indicator',
      'plan',
      'clock_record',
      'reminder',
      'user_profile',
      'health_report',
      'meal_record',
      'meal_recipe',
      'meal_settings',
      'ai_message',
      'ai_session',
      'quit_smoking_profile',
      'smoking_event',
      'sync_queue',
    ]) {
      await db.delete(table);
    }
    notifyListeners();
  }

  Future<void> updateIndicator(int id, Map<String, dynamic> payload) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'health_indicator',
      {'payload_json': jsonEncode(payload), 'updated_at': now, 'is_dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    final updatedRows = await db.query(
      'health_indicator',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, kLocalUserId],
      limit: 1,
    );
    if (updatedRows.isNotEmpty) {
      final updated = HealthIndicatorEntry.fromRow(updatedRows.first);
      await _applyCriticalIndicatorSafety(updated.type, db);
    }
    notifyListeners();
  }

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  Future<ClockStats> loadClockStats() async {
    final db = await database.open();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(
      Duration(days: todayStart.weekday - 1),
    );
    final monthStart = DateTime(now.year, now.month, 1);

    Future<Map<String, int>> countByType(DateTime start, DateTime end) async {
      final rows = await db.query(
        'clock_record',
        where: 'user_id = ? AND clock_at >= ? AND clock_at < ? AND status = ?',
        whereArgs: [
          kLocalUserId,
          start.millisecondsSinceEpoch,
          end.millisecondsSinceEpoch,
          'done',
        ],
      );
      final map = <String, int>{};
      for (final row in rows) {
        final type = row['type'] as String? ?? '';
        map[type] = (map[type] ?? 0) + 1;
      }
      return map;
    }

    final todayEnd = todayStart.add(const Duration(days: 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final todayCounts = await countByType(todayStart, todayEnd);
    final weekCounts = await countByType(weekStart, weekEnd);
    final monthCounts = await countByType(monthStart, monthEnd);

    final todayDays = 1;
    final weekDays = now.difference(weekStart).inDays + 1;
    final monthDays = now.difference(monthStart).inDays + 1;

    return ClockStats(
      today: todayCounts,
      week: weekCounts,
      month: monthCounts,
      todayDays: todayDays,
      weekDays: weekDays,
      monthDays: monthDays,
    );
  }

  void signalChanged() => notifyListeners();

  // ── 数据导出 ─────────────────────────────────────────────────────

  /// 全量 JSON 备份，包含档案/指标/提醒/打卡记录
  Future<Map<String, dynamic>> exportJson() async {
    final db = await database.open();
    final profileRows = await db.query(
      'user_profile',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
    );
    final indicatorRows = await db.query(
      'health_indicator',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
    );
    final reminderRows = await db.query(
      'reminder',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
    );
    final clockRows = await db.query(
      'clock_record',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
    );
    final quitProfileRows = await db.query('quit_smoking_profile');
    final smokingEventRows = await db.query('smoking_event');
    final mealRows = await db.query(
      'meal_record',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
    );
    final mealRecipeRows = await db.query(
      'meal_recipe',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
    );
    final mealSettingsRows = await db.query(
      'meal_settings',
      where: 'user_id = ?',
      whereArgs: [kLocalUserId],
    );
    return {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'data': {
        'userProfile': profileRows,
        'indicators': indicatorRows,
        'reminders': reminderRows,
        'clockRecords': clockRows,
        'quitSmokingProfile': quitProfileRows,
        'smokingEvents': smokingEventRows,
        'mealRecords': mealRows,
        'mealRecipes': mealRecipeRows,
        'mealSettings': mealSettingsRows,
      },
    };
  }

  /// CSV 导出（仅健康指标，适合用 Excel/Numbers 分析）
  Future<String> exportCsv() async {
    final indicators = await loadIndicators(limit: 5000);
    final buf = StringBuffer('日期,时间,指标类型,数值,单位,备注\n');
    String p2(int n) => n.toString().padLeft(2, '0');
    for (final e in indicators) {
      final dt = e.measuredTime;
      final date = '${dt.year}-${p2(dt.month)}-${p2(dt.day)}';
      final time = '${p2(dt.hour)}:${p2(dt.minute)}';
      switch (e.type) {
        case 'bp':
          buf.writeln('$date,$time,收缩压,${e.payload['systolic'] ?? ''},mmHg,');
          buf.writeln('$date,$time,舒张压,${e.payload['diastolic'] ?? ''},mmHg,');
          if (e.payload['heartRate'] != null) {
            buf.writeln('$date,$time,心率（测压时）,${e.payload['heartRate']},bpm,');
          }
        case 'weight':
          buf.writeln('$date,$time,体重,${e.payload['weightKg'] ?? ''},kg,');
        case 'glucose':
          final mt = switch (e.payload['mealType']) {
            'fasting' => '空腹',
            'postmeal' => '餐后2h',
            _ => '随机',
          };
          buf.writeln(
            '$date,$time,血糖,${e.payload['glucoseMmol'] ?? ''},mmol/L,$mt',
          );
        case 'heart_rate':
          buf.writeln('$date,$time,心率,${e.payload['bpm'] ?? ''},bpm,');
        case 'lipid':
          if (e.payload['tc'] != null) {
            buf.writeln('$date,$time,总胆固醇 TC,${e.payload['tc']},mmol/L,');
          }
          if (e.payload['ldl'] != null) {
            buf.writeln('$date,$time,LDL 低密度,${e.payload['ldl']},mmol/L,');
          }
          if (e.payload['hdl'] != null) {
            buf.writeln('$date,$time,HDL 高密度,${e.payload['hdl']},mmol/L,');
          }
          if (e.payload['tg'] != null) {
            buf.writeln('$date,$time,甘油三酯 TG,${e.payload['tg']},mmol/L,');
          }
        case 'body_fat':
          buf.writeln('$date,$time,体脂率,${e.payload['bodyFatPct'] ?? ''},%,');
        case 'waist':
          buf.writeln('$date,$time,腰围,${e.payload['waistCm'] ?? ''},cm,');
        case 'spo2':
          buf.writeln('$date,$time,血氧饱和度,${e.payload['spo2Pct'] ?? ''},%,');
        case 'sleep':
          final q = switch (e.payload['quality']) {
            'good' => '好',
            'fair' => '一般',
            _ => '差',
          };
          buf.writeln('$date,$time,睡眠时长,${e.payload['sleepHours'] ?? ''},h,$q');
        case 'steps':
          buf.writeln('$date,$time,步数,${e.payload['steps'] ?? ''},步,');
        case 'bmi':
          buf.writeln('$date,$time,BMI,${e.payload['bmiValue'] ?? ''},,自动计算');
      }
    }
    return buf.toString();
  }

  // ── 数据导入（恢复） ─────────────────────────────────────────────

  /// 从 JSON 备份文件恢复数据，返回导入的指标条数
  Future<int> importJson(Map<String, dynamic> data) async {
    final exportData = data['data'] as Map<String, dynamic>?;
    if (exportData == null) throw const FormatException('文件格式不正确，缺少 data 字段');
    final db = await database.open();
    int indicatorCount = 0;

    await db.transaction((txn) async {
      // 清除现有记录（保留 plan，恢复后可重新生成）
      await txn.delete(
        'health_indicator',
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
      );
      await txn.delete(
        'reminder',
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
      );
      await txn.delete(
        'clock_record',
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
      );
      await txn.delete('quit_smoking_profile');
      await txn.delete('smoking_event');
      await txn.delete(
        'meal_record',
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
      );
      await txn.delete(
        'meal_recipe',
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
      );
      await txn.delete(
        'meal_settings',
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
      );

      // 导入指标
      final indicators = exportData['indicators'] as List?;
      if (indicators != null) {
        for (final row in indicators) {
          final map = Map<String, Object?>.from(row as Map);
          map['user_id'] = kLocalUserId;
          map.remove('id');
          await txn.insert('health_indicator', map);
          indicatorCount++;
        }
      }

      // 导入提醒
      final reminders = exportData['reminders'] as List?;
      if (reminders != null) {
        for (final row in reminders) {
          final map = Map<String, Object?>.from(row as Map);
          map['user_id'] = kLocalUserId;
          map.remove('id');
          await txn.insert('reminder', map);
        }
      }

      // 导入打卡记录
      final clockRecords = exportData['clockRecords'] as List?;
      if (clockRecords != null) {
        for (final row in clockRecords) {
          final map = Map<String, Object?>.from(row as Map);
          map['user_id'] = kLocalUserId;
          map.remove('id');
          await txn.insert('clock_record', map);
        }
      }

      final quitProfiles = exportData['quitSmokingProfile'] as List?;
      if (quitProfiles != null && quitProfiles.isNotEmpty) {
        final map = Map<String, Object?>.from(quitProfiles.first as Map)
          ..remove('id');
        await txn.insert('quit_smoking_profile', map);
      }
      final smokingEvents = exportData['smokingEvents'] as List?;
      if (smokingEvents != null) {
        for (final row in smokingEvents) {
          final map = Map<String, Object?>.from(row as Map)..remove('id');
          await txn.insert('smoking_event', map);
        }
      }

      for (final entry in [
        ('mealRecords', 'meal_record'),
        ('mealRecipes', 'meal_recipe'),
        ('mealSettings', 'meal_settings'),
      ]) {
        final rows = exportData[entry.$1] as List?;
        if (rows == null) continue;
        for (final row in rows) {
          final map = Map<String, Object?>.from(row as Map)
            ..['user_id'] = kLocalUserId
            ..remove('id');
          await txn.insert(entry.$2, map);
        }
      }

      // 导入档案（合并：有则更新，无则插入）
      final profileList = exportData['userProfile'] as List?;
      if (profileList != null && profileList.isNotEmpty) {
        final profileMap = Map<String, Object?>.from(profileList.first as Map);
        profileMap['user_id'] = kLocalUserId;
        profileMap.remove('id');
        profileMap['updated_at'] = DateTime.now().millisecondsSinceEpoch;
        final existing = await txn.query(
          'user_profile',
          where: 'user_id = ?',
          whereArgs: [kLocalUserId],
        );
        if (existing.isEmpty) {
          await txn.insert('user_profile', profileMap);
        } else {
          await txn.update(
            'user_profile',
            profileMap,
            where: 'user_id = ?',
            whereArgs: [kLocalUserId],
          );
        }
      }
    });

    notifyListeners();
    return indicatorCount;
  }

  Future<void> _insertDefaultReminders(AppDatabase db, int timestamp) async {
    final now = DateTime.now();
    final templates = [
      ('weight', 7, 0, '晨起空腹称重'),
      ('meal', 11, 0, '午餐前确认今日饮食'),
      ('exercise', 18, 30, '晚间中等强度运动'),
      ('medicine', 21, 0, '如有医嘱，按时用药'),
    ];
    for (final item in templates) {
      await db.insert(
        'reminder',
        ReminderData(
          type: item.$1,
          remindAt: DateTime(
            now.year,
            now.month,
            now.day,
            item.$2,
            item.$3,
          ).millisecondsSinceEpoch,
          payload: {'note': item.$4},
          channel: 'local',
          status: 'pending',
          createdAt: timestamp,
          updatedAt: timestamp,
        ).toRow(),
      );
    }
  }

  // ignore: unused_element
  List<Map<String, dynamic>> _buildMealTemplates({
    required int targetKcal,
    required String dietPreference,
    required String goal,
    required bool highBp,
    required bool highGlucose,
    required bool highLipid,
    required String dietNote,
    required String goalNote,
  }) {
    final isVeg = dietPreference == 'vegetarian';
    final isLight = dietPreference == 'light' || highBp || highLipid;
    final oilNote = isLight ? '少油（植物油 < 15g/天）' : '适量植物油';
    final carb = highGlucose ? '糙米 / 荞麦 / 红薯（低GI）' : '糙米 / 燕麦 / 全麦';
    final summary = '$targetKcal kcal，$dietNote';

    final proteins = isVeg
        ? [
            '豆腐 100g',
            '鸡蛋 1个 + 豆腐 80g',
            '毛豆 50g + 腰果',
            '豆腐干 + 坚果',
            '鸡蛋 2个',
            '毛豆 + 豆浆',
            '黄豆 + 豆腐',
          ]
        : [
            '鸡胸肉 120g',
            '清蒸鱼 150g',
            '虾仁 100g',
            '牛肉 100g',
            '三文鱼 100g',
            '鸡腿肉（去皮）130g',
            '猪瘦肉 80g',
          ];

    return [
      // 第1天
      {
        'summary': summary,
        'goalNote': goalNote,
        'breakfast': ['燕麦粥 1碗（$carb）', '水煮蛋 1个', '牛奶 200ml'],
        'lunch': ['$carb 100g（熟重）', proteins[0], '西兰花 + 胡萝卜 200g', oilNote],
        'dinner': ['$carb 80g', '清蒸鱼 120g', '菠菜 + 蘑菇 200g'],
        'snack': ['苹果半个 / 无糖酸奶 100g'],
      },
      // 第2天
      {
        'summary': summary,
        'goalNote': goalNote,
        'breakfast': ['全麦吐司 2片', proteins[2], '番茄 1个'],
        'lunch': ['荞麦面 100g（煮熟）', proteins[1], '黄瓜 + 生菜 200g', oilNote],
        'dinner': ['红薯 150g', proteins[2], '大量绿叶菜 250g'],
        'snack': ['坚果 10g / 蓝莓 50g'],
      },
      // 第3天
      {
        'summary': summary,
        'goalNote': goalNote,
        'breakfast': ['杂粮粥 1碗', '鸡蛋 1个', '黄瓜片'],
        'lunch': ['糙米饭 100g', proteins[3], '彩椒 + 西葫芦 200g', oilNote],
        'dinner': ['玉米 1根', proteins[4], '芹菜 + 木耳 200g'],
        'snack': ['梨半个 / 低脂奶酪 20g'],
      },
      // 第4天
      {
        'summary': summary,
        'goalNote': goalNote,
        'breakfast': ['燕麦片 + 坚果', '无糖豆浆 200ml', '番茄 1个'],
        'lunch': ['藜麦沙拉（藜麦 80g + 蔬菜）', proteins[5], oilNote],
        'dinner': ['糙米饭 80g', proteins[0], '莲藕 + 绿叶菜 200g'],
        'snack': ['柚子片 / 无糖酸奶'],
      },
      // 第5天
      {
        'summary': summary,
        'goalNote': goalNote,
        'breakfast': ['全麦面包 2片', '鸡蛋 + 牛油果片', '牛奶 200ml'],
        'lunch': ['糙米饭 100g', proteins[1], '上汤娃娃菜 200g', oilNote],
        'dinner': ['红薯 + 玉米各半', proteins[3], '蒸南瓜 + 绿叶菜'],
        'snack': ['小番茄 10颗 / 坚果 10g'],
      },
      // 第6天
      {
        'summary': summary,
        'goalNote': goalNote,
        'breakfast': ['燕麦粥 + 枸杞', proteins[6], '菠菜汁'],
        'lunch': ['荞麦面 + 豆腐汤', proteins[4], '大量绿叶菜', oilNote],
        'dinner': ['糙米饭 80g', proteins[5], '茄子 + 冬瓜 200g'],
        'snack': ['苹果 1个 / 无糖豆浆'],
      },
      // 第7天
      {
        'summary': '$targetKcal kcal，稍作灵活调整（可适量补充偏好食物）',
        'goalNote': goalNote,
        'breakfast': ['杂粮粥', '鸡蛋 + 素菜', '无糖豆浆'],
        'lunch': ['糙米 + 蒸红薯 100g', proteins[2], '时令蔬菜 250g', oilNote],
        'dinner': ['玉米汤 + 糙米少量', proteins[6], '西兰花 + 胡萝卜'],
        'snack': ['坚果 + 低糖水果'],
      },
    ];
  }

  List<Map<String, dynamic>> _buildExerciseTemplates({
    required String exerciseBase,
    required bool highBp,
    required bool obese,
    required String goal,
  }) {
    final durations = switch (exerciseBase) {
      'none' => [20, 15, 15, 25, 15, 25, 10],
      'light' => [30, 25, 20, 30, 25, 35, 15],
      'moderate' => [40, 35, 25, 40, 35, 45, 20],
      _ => [20, 15, 15, 25, 15, 25, 10],
    };

    final intensity = switch (exerciseBase) {
      'none' => '低强度',
      'light' => (highBp ? '中低强度' : '中等强度'),
      'moderate' => (highBp ? '中等强度' : '中高强度'),
      _ => '低强度',
    };

    final cardioType = obese
        ? '快走 / 游泳 / 固定单车（低冲击）'
        : (highBp ? '快走 / 椭圆机 / 游泳' : '慢跑 / 椭圆机 / 跳绳');

    final strengthNote =
        highBp ? '中等重量，避免憋气，组间充分休息' : (obese ? '低重量开始，注意膝关节保护' : '循序渐进加重');

    Map<String, dynamic> step(
      String name, {
      int? sets,
      String? reps,
      int? minutes,
      int? restSeconds,
      required String instruction,
    }) =>
        {
          'name': name,
          if (sets != null) 'sets': sets,
          if (reps != null) 'reps': reps,
          if (minutes != null) 'durationMinutes': minutes,
          if (restSeconds != null) 'restSeconds': restSeconds,
          'instruction': instruction,
        };

    Map<String, dynamic> plan({
      required String title,
      required String goalText,
      required int totalMinutes,
      required List<Map<String, dynamic>> warmup,
      required List<Map<String, dynamic>> main,
      required List<Map<String, dynamic>> cooldown,
      List<String> equipment = const [],
      Map<String, dynamic>? alternative,
    }) {
      final safetyNotes = <String>[
        '以主观用力程度 RPE 4–6/10 为宜，能说完整句子但呼吸略加快。',
        strengthNote,
        '出现胸痛、明显气短、眩晕或关节锐痛时立即停止，并视情况就医。',
      ];
      return {
        'summary': '$title · $totalMinutes 分钟 · $intensity',
        'type': title,
        'goal': goalText,
        'duration': totalMinutes,
        'durationMinutes': totalMinutes,
        'intensity': intensity,
        'location': '居家或户外平坦场地',
        'equipment': equipment,
        'warmup': warmup,
        'main': main,
        'cooldown': cooldown,
        'safetyNotes': safetyNotes,
        if (alternative != null) 'alternative': alternative,
        'items': [
          for (final item in warmup) _exerciseStepText('热身', item),
          for (final item in main) _exerciseStepText('主训练', item),
          for (final item in cooldown) _exerciseStepText('放松', item),
          for (final note in safetyNotes) '注意 · $note',
        ],
      };
    }

    final goalText = switch (goal) {
      'fat_loss' => '提高日常消耗并保持可持续运动节奏',
      'glucose_control' => '改善餐后活动量与全身肌肉参与',
      'bp_control' => '提升心肺耐力，避免屏气和突然用力',
      _ => '建立有氧、力量与恢复均衡的一周节奏',
    };

    return [
      plan(
        title: '稳态有氧',
        goalText: goalText,
        totalMinutes: durations[0],
        warmup: [
          step('原地踏步与肩颈活动', minutes: 5, instruction: '逐步加快步频，肩部自然放松'),
        ],
        main: [
          step(cardioType,
              minutes: (durations[0] - 10).clamp(5, 35),
              instruction: '保持均匀呼吸和稳定节奏，不追求速度'),
        ],
        cooldown: [
          step('慢走与小腿拉伸', minutes: 5, instruction: '心率平稳后再结束运动'),
        ],
        alternative: {
          'condition': '膝踝不适或天气不佳',
          'name': '室内原地踏步',
          'instruction': '扶稳桌椅，采用低抬腿动作并缩短单次时长',
        },
      ),
      plan(
        title: '上肢力量与核心',
        goalText: '改善肩背力量和躯干稳定，动作全程避免憋气',
        totalMinutes: durations[1],
        equipment: const ['弹力带或轻哑铃', '稳固椅子'],
        warmup: [
          step('肩绕环与扩胸运动', minutes: 5, instruction: '小幅度开始，避免耸肩'),
        ],
        main: [
          step('弹力带划船',
              sets: 3,
              reps: '10–12次',
              restSeconds: 45,
              instruction: '肩胛骨向后下方收紧，腰背保持中立'),
          step('墙面俯卧撑',
              sets: 3,
              reps: '8–12次',
              restSeconds: 60,
              instruction: '身体保持直线，呼气推起'),
          step('坐姿哑铃弯举',
              sets: 2,
              reps: '10–12次',
              restSeconds: 45,
              instruction: '上臂贴近身体，不借力摆动'),
          step('鸟狗式',
              sets: 2,
              reps: '每侧8次',
              restSeconds: 45,
              instruction: '缓慢伸展对侧手脚，骨盆保持稳定'),
        ],
        cooldown: [
          step('胸肩与背部拉伸', minutes: 5, instruction: '每个动作保持20–30秒，不弹震'),
        ],
      ),
      plan(
        title: '主动恢复',
        goalText: '缓解疲劳并维持日常活动量',
        totalMinutes: durations[2],
        warmup: [
          step('腹式呼吸', minutes: 2, instruction: '吸气腹部隆起，缓慢呼气'),
        ],
        main: [
          step('餐后轻松步行',
              sets: 2,
              reps: '每次5–10分钟',
              restSeconds: 60,
              instruction: '步速舒适，以放松为主'),
          step('肩颈活动', minutes: 5, instruction: '缓慢点头、转头和肩部绕环'),
        ],
        cooldown: [
          step('全身舒展', minutes: 3, instruction: '配合呼吸放松背部和下肢'),
        ],
      ),
      plan(
        title: '有氧与核心稳定',
        goalText: '在心肺训练后强化躯干控制',
        totalMinutes: durations[3],
        equipment: const ['瑜伽垫'],
        warmup: [
          step('动态热身', minutes: 5, instruction: '原地踏步、髋部绕环和踝关节活动'),
        ],
        main: [
          step(cardioType,
              minutes: (durations[3] - 15).clamp(5, 30),
              instruction: '维持RPE 4–6/10，呼吸均匀'),
          step('高位平板支撑',
              sets: 3,
              reps: '20–30秒',
              restSeconds: 45,
              instruction: '可扶桌面完成，收紧腹部不塌腰'),
          step('仰卧交替抬脚',
              sets: 2, reps: '每侧8次', restSeconds: 45, instruction: '腰部贴垫，动作缓慢'),
        ],
        cooldown: [
          step('髋屈肌与腰背拉伸', minutes: 5, instruction: '保持自然呼吸'),
        ],
      ),
      plan(
        title: '下肢力量',
        goalText: '强化臀腿力量并提高日常起坐稳定性',
        totalMinutes: durations[4],
        equipment: const ['稳固椅子'],
        warmup: [
          step('踝泵与髋膝活动', minutes: 5, instruction: '扶稳椅背，小范围逐步增加'),
        ],
        main: [
          step('椅子坐站',
              sets: 3,
              reps: '8–12次',
              restSeconds: 60,
              instruction: '膝盖对准脚尖，起身时呼气'),
          step('臀桥',
              sets: 3,
              reps: '10–15次',
              restSeconds: 45,
              instruction: '收紧臀部，不用腰部顶起'),
          step('扶椅提踵',
              sets: 3,
              reps: '12–15次',
              restSeconds: 45,
              instruction: '缓慢抬起和落下，保持身体稳定'),
        ],
        cooldown: [
          step('臀腿与小腿拉伸', minutes: 5, instruction: '无痛范围内保持20–30秒'),
        ],
        alternative: {
          'condition': '膝关节不适',
          'name': '坐姿抬腿',
          'instruction': '坐稳后交替伸膝，每侧完成2组8–10次',
        },
      ),
      plan(
        title: '耐力有氧',
        goalText: '完成本周最长一次连续有氧，仍以舒适节奏为主',
        totalMinutes: durations[5],
        warmup: [
          step('慢走与动态活动', minutes: 7, instruction: '逐步提高步频，不突然加速'),
        ],
        main: [
          step(cardioType,
              minutes: (durations[5] - 14).clamp(6, 35),
              instruction: '每10分钟检查一次呼吸和身体感受'),
        ],
        cooldown: [
          step('慢走、下肢拉伸', minutes: 7, instruction: '逐步降低心率后补充饮水'),
        ],
      ),
      plan(
        title: '恢复与活动度',
        goalText: '让身体恢复，为下一周训练做准备',
        totalMinutes: durations[6],
        equipment: const ['瑜伽垫（可选）'],
        warmup: [
          step('轻松散步', minutes: 5, instruction: '保持自然步速'),
        ],
        main: [
          step('全身活动度练习',
              minutes: (durations[6] - 8).clamp(4, 12),
              instruction: '依次活动肩、胸椎、髋和踝关节'),
        ],
        cooldown: [
          step('呼吸放松', minutes: 3, instruction: '缓慢呼吸，放松全身肌肉'),
        ],
      ),
    ];
  }

  // ignore: unused_element
  Map<String, dynamic> _buildMeasurementPlan({
    required bool highBp,
    required bool highGlucose,
    required String goal,
  }) {
    final items = <String>['晨起空腹体重（如厕后、早餐前）'];
    if (highBp) {
      items.add('早晨血压（起床安静休息 5 分钟后）');
      items.add('晚间血压（19:00-21:00，安静状态）');
    }
    if (highGlucose) {
      items.add('空腹血糖（早餐前）');
      items.add('餐后 2 小时血糖（早餐 / 午餐后计时）');
    }
    if (goal == 'fat_loss') {
      items.add('记录今日饮食摄入（估算热量）');
    }
    return {'summary': '今日 ${items.length} 项测量', 'items': items};
  }
}

class _RiskResult {
  const _RiskResult({
    required this.risks,
    required this.highBp,
    required this.borderlineBp,
    required this.highGlucose,
    required this.borderlineGlucose,
    required this.highLipid,
    required this.borderlineLipid,
    required this.obese,
    required this.targetKcal,
    required this.bmr,
    required this.goalNote,
    required this.dietNote,
    this.crisisBp = false,
    this.lowHdl = false,
    this.highTg = false,
    this.highBodyFat = false,
    this.highWaist = false,
    this.lowSpo2 = false,
    this.dangerSpo2 = false,
    this.shortSleep = false,
    this.lowSteps = false,
    // 实际指标数值（用于生成个性化摘要）
    this.systolic = 0,
    this.diastolic = 0,
    this.glucoseMmol = 0,
    this.tc = 0,
    this.ldl = 0,
    this.bmi = 0,
    this.steps = 0,
    this.spo2 = 0,
  });

  final List<String> risks;
  final bool highBp, borderlineBp, crisisBp;
  final bool highGlucose, borderlineGlucose;
  final bool highLipid, borderlineLipid, lowHdl, highTg;
  final bool obese;
  final bool highBodyFat, highWaist;
  final bool lowSpo2, dangerSpo2;
  final bool shortSleep;
  final bool lowSteps;
  final int targetKcal, bmr;
  final String goalNote, dietNote;
  // 实际值
  final int systolic, diastolic, spo2, steps;
  final double glucoseMmol, tc, ldl, bmi;

  Map<String, dynamic> toPayload() {
    final isCritical = crisisBp || dangerSpo2;
    return {
      'summary': _buildSummary(),
      'risks': risks,
      'isCritical': isCritical,
      'targetKcal': isCritical ? 0 : targetKcal,
      'bmr': isCritical ? 0 : bmr,
      'goalNote': isCritical ? '检测到紧急健康风险，请立即就医。' : goalNote,
      'dietNote': isCritical ? '' : dietNote,
    };
  }

  String _buildSummary() {
    if (risks.isEmpty) return _buildHealthySummary();
    if (crisisBp || dangerSpo2) {
      return '检测到紧急健康风险，请立即就医，暂不提供健康或运动计划。';
    }

    // 有风险：按严重程度描述主要问题
    final severe = risks
        .where(
          (r) => r.contains('危象') || r.contains('糖尿病标准') || r.contains('危险偏低'),
        )
        .toList();
    if (severe.isNotEmpty) {
      return '检测到 ${severe.length} 项需立即关注的指标，请尽快就医确认，同时参考以下计划调整生活方式。';
    }
    return '检测到 ${risks.length} 项指标偏离正常范围，本次计划已针对性调整，建议同时咨询医生。';
  }

  String _buildHealthySummary() {
    // 个性化展示已测指标数值
    final parts = <String>[];
    if (systolic > 0 && diastolic > 0) {
      parts.add('血压 $systolic/$diastolic mmHg');
    }
    if (glucoseMmol > 0) {
      parts.add('血糖 ${glucoseMmol.toStringAsFixed(1)} mmol/L');
    }
    if (tc > 0) {
      parts.add('TC ${tc.toStringAsFixed(1)} mmol/L');
    }
    if (bmi > 0) {
      parts.add('BMI ${bmi.toStringAsFixed(1)}');
    }

    // 生成维持建议
    final tips = <String>[];
    if (steps > 0 && steps < 10000) {
      tips.add('步数可进一步提升至 10000 步');
    }
    if (spo2 > 0 && spo2 < 98) {
      tips.add('保持深呼吸与适量有氧运动');
    }
    if (tips.isEmpty) {
      tips.add('继续规律监测，保持现有生活习惯');
    }

    if (parts.isEmpty) {
      return '已录入的指标暂未发现异常。${tips.first}。';
    }

    final valueText = parts.join('、');
    return '$valueText 均在正常范围。${tips.first}。';
  }
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String _reminderDefinitionKey(ReminderData reminder) => jsonEncode({
      'type': reminder.type,
      'remindAt': reminder.remindAt,
      'channel': reminder.channel,
      'payload': _canonicalReminderValue(reminder.payload),
    });

Object? _canonicalReminderValue(Object? value) {
  const ignoredKeys = {
    'ackHistory',
    'actionHistory',
    'archived',
    'inventoryRemaining',
  };
  if (value is Map) {
    final keys = value.keys
        .map((key) => key.toString())
        .where((key) => !ignoredKeys.contains(key))
        .toList()
      ..sort();
    return {
      for (final key in keys) key: _canonicalReminderValue(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalReminderValue).toList(growable: false);
  }
  return value;
}

String _reminderOccurrenceKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
