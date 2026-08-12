import 'dart:convert';

const String kLocalUserId = 'local-user';

abstract final class HealthRanges {
  static const int minAge = 18;
  static const int maxAge = 100;
  static const double minHeightCm = 100;
  static const double maxHeightCm = 230;
  static const double minWeightKg = 20;
  static const double maxWeightKg = 300;
  static const double minSystolic = 60;
  static const double maxSystolic = 250;
  static const double minDiastolic = 40;
  static const double maxDiastolic = 160;
  static const double minGlucoseMmol = 1;
  static const double maxGlucoseMmol = 40;
  static const double minTcMmol = 1;
  static const double maxTcMmol = 20;
  static const double minLdlMmol = 0.5;
  static const double maxLdlMmol = 15;
}

abstract final class HealthSafety {
  static bool isCriticalIndicator(String type, Map<String, dynamic> payload) {
    if (type == 'bp') {
      final systolic = (payload['systolic'] as num?)?.toDouble() ?? 0;
      final diastolic = (payload['diastolic'] as num?)?.toDouble() ?? 0;
      return systolic >= 180 || diastolic >= 120;
    }
    if (type == 'spo2') {
      final spo2 = (payload['spo2Pct'] as num?)?.toDouble() ?? 0;
      return spo2 > 0 && spo2 < 90;
    }
    return false;
  }

  static bool isAbnormalIndicator(String type, Map<String, dynamic> payload) {
    return switch (type) {
      'bp' => ((payload['systolic'] as num?)?.toDouble() ?? 0) >= 130 ||
          ((payload['diastolic'] as num?)?.toDouble() ?? 0) >= 80,
      'glucose' => ((payload['glucoseMmol'] as num?)?.toDouble() ?? 0) >=
          (payload['mealType'] == 'postmeal' ? 7.8 : 5.6),
      'spo2' => ((payload['spo2Pct'] as num?)?.toDouble() ?? 100) < 95,
      'heart_rate' => ((payload['bpm'] as num?)?.toDouble() ?? 70) < 60 ||
          ((payload['bpm'] as num?)?.toDouble() ?? 70) > 100,
      'lipid' => ((payload['tc'] as num?)?.toDouble() ?? 0) >= 5.18 ||
          ((payload['ldl'] as num?)?.toDouble() ?? 0) >= 3.37,
      'sleep' => ((payload['sleepHours'] as num?)?.toDouble() ?? 8) < 7,
      _ => false,
    };
  }
}

class UserProfileData {
  const UserProfileData({
    this.id,
    this.userId = kLocalUserId,
    required this.nickname,
    required this.gender,
    required this.birthYear,
    required this.heightCm,
    required this.weightKg,
    required this.medicalHistory,
    required this.medications,
    required this.createdAt,
    required this.updatedAt,
    this.goal = 'maintain',
    this.exerciseBase = 'none',
    this.dietPreference = 'normal',
    this.version = 0,
    this.isDirty = 1,
  });

  final int? id;
  final String userId;
  final String nickname;
  final String gender;
  final int birthYear;
  final double heightCm;
  final double weightKg;
  final String medicalHistory;
  final String medications;
  final int createdAt;
  final int updatedAt;
  // fat_loss | glucose_control | bp_control | maintain
  final String goal;
  // none | light | moderate
  final String exerciseBase;
  // light | normal | vegetarian | custom
  final String dietPreference;
  final int version;
  final int isDirty;

  int get age {
    final value = DateTime.now().year - birthYear;
    if (value < HealthRanges.minAge || value > HealthRanges.maxAge) return 0;
    return value;
  }

  double get bmi {
    if (heightCm <= 0 || weightKg <= 0) return 0;
    final meters = heightCm / 100;
    return weightKg / (meters * meters);
  }

  String get bmiLevel {
    final value = bmi;
    if (value == 0) return '待完善';
    if (value < 18.5) return '偏瘦';
    if (value < 24) return '正常';
    if (value < 28) return '超重';
    return '肥胖';
  }

  bool get isComplete =>
      (gender == 'female' || gender == 'male') &&
      age >= HealthRanges.minAge &&
      heightCm >= HealthRanges.minHeightCm &&
      heightCm <= HealthRanges.maxHeightCm &&
      weightKg >= HealthRanges.minWeightKg &&
      weightKg <= HealthRanges.maxWeightKg;

  UserProfileData copyWith({
    int? id,
    String? userId,
    String? nickname,
    String? gender,
    int? birthYear,
    double? heightCm,
    double? weightKg,
    String? medicalHistory,
    String? medications,
    int? createdAt,
    int? updatedAt,
    String? goal,
    String? exerciseBase,
    String? dietPreference,
    int? version,
    int? isDirty,
  }) {
    return UserProfileData(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      nickname: nickname ?? this.nickname,
      gender: gender ?? this.gender,
      birthYear: birthYear ?? this.birthYear,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      medicalHistory: medicalHistory ?? this.medicalHistory,
      medications: medications ?? this.medications,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      goal: goal ?? this.goal,
      exerciseBase: exerciseBase ?? this.exerciseBase,
      dietPreference: dietPreference ?? this.dietPreference,
      version: version ?? this.version,
      isDirty: isDirty ?? this.isDirty,
    );
  }

  factory UserProfileData.empty() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return UserProfileData(
      nickname: '',
      gender: 'unknown',
      birthYear: 0,
      heightCm: 0,
      weightKg: 0,
      medicalHistory: '',
      medications: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  factory UserProfileData.fromRow(Map<String, Object?> row) {
    return UserProfileData(
      id: _asInt(row['id']),
      userId: row['user_id'] as String? ?? kLocalUserId,
      nickname: row['nickname'] as String? ?? '',
      gender: row['gender'] as String? ?? 'unknown',
      birthYear: _asInt(row['birth_year']) ?? 0,
      heightCm: _asDouble(row['height_cm']),
      weightKg: _asDouble(row['weight_kg']),
      medicalHistory: row['medical_history'] as String? ?? '',
      medications: row['medications'] as String? ?? '',
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
      goal: row['goal'] as String? ?? 'maintain',
      exerciseBase: row['exercise_base'] as String? ?? 'none',
      dietPreference: row['diet_preference'] as String? ?? 'normal',
      version: _asInt(row['version']) ?? 0,
      isDirty: _asInt(row['is_dirty']) ?? 1,
    );
  }

  Map<String, Object?> toRow() {
    return {
      'user_id': userId,
      'nickname': nickname,
      'gender': gender,
      'birth_year': birthYear,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'medical_history': medicalHistory,
      'medications': medications,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'goal': goal,
      'exercise_base': exerciseBase,
      'diet_preference': dietPreference,
      'version': version,
      'is_dirty': isDirty,
    };
  }
}

class HealthIndicatorEntry {
  const HealthIndicatorEntry({
    this.id,
    this.userId = kLocalUserId,
    this.clientId,
    required this.type,
    required this.payload,
    required this.source,
    required this.measuredAt,
    required this.createdAt,
    required this.updatedAt,
    this.version = 0,
    this.isDirty = 1,
    this.syncAt = 0,
  });

  final int? id;
  final String userId;
  final String? clientId;
  final String type;
  final Map<String, dynamic> payload;
  final String source;
  final int measuredAt;
  final int createdAt;
  final int updatedAt;
  final int version;
  final int isDirty;
  final int syncAt;

  DateTime get measuredTime => DateTime.fromMillisecondsSinceEpoch(measuredAt);

  String get label {
    return switch (type) {
      'bp' => '血压',
      'weight' => '体重',
      'glucose' => '血糖',
      'lipid' => '血脂',
      'heart_rate' => '心率',
      'body_fat' => '体脂率',
      'waist' => '腰围',
      'spo2' => '血氧',
      'sleep' => '睡眠',
      'steps' => '步数',
      'bmi' => 'BMI',
      _ => '健康指标',
    };
  }

  String get displayValue {
    return switch (type) {
      'bp' => '${_fmt(payload['systolic'])}/${_fmt(payload['diastolic'])} mmHg',
      'weight' => '${_fmt(payload['weightKg'], digits: 1)} kg',
      'glucose' => '${_fmt(payload['glucoseMmol'], digits: 1)} mmol/L',
      'lipid' =>
        'TC ${_fmt(payload['tc'], digits: 1)} / LDL ${_fmt(payload['ldl'], digits: 1)}',
      'heart_rate' => '${_fmt(payload['bpm'])} bpm',
      'body_fat' => '${_fmt(payload['bodyFatPct'], digits: 1)} %',
      'waist' => '${_fmt(payload['waistCm'], digits: 1)} cm',
      'spo2' => '${_fmt(payload['spo2Pct'])} %',
      'sleep' => '${_fmt(payload['sleepHours'], digits: 1)} h',
      'steps' => '${_fmt(payload['steps'])} 步',
      'bmi' => _fmt(payload['bmiValue'], digits: 1),
      _ => payload.values.map((e) => '$e').join(' / '),
    };
  }

  double? get numericTrendValue {
    return switch (type) {
      'weight' => _asDoubleOrNull(payload['weightKg']),
      'bp' => _asDoubleOrNull(payload['systolic']),
      'glucose' => _asDoubleOrNull(payload['glucoseMmol']),
      'heart_rate' => _asDoubleOrNull(payload['bpm']),
      'body_fat' => _asDoubleOrNull(payload['bodyFatPct']),
      'waist' => _asDoubleOrNull(payload['waistCm']),
      'spo2' => _asDoubleOrNull(payload['spo2Pct']),
      'sleep' => _asDoubleOrNull(payload['sleepHours']),
      'steps' => _asDoubleOrNull(payload['steps']),
      'bmi' => _asDoubleOrNull(payload['bmiValue']),
      _ => null,
    };
  }

  factory HealthIndicatorEntry.fromRow(Map<String, Object?> row) {
    return HealthIndicatorEntry(
      id: _asInt(row['id']),
      userId: row['user_id'] as String? ?? kLocalUserId,
      clientId: row['client_id'] as String?,
      type: row['type'] as String? ?? 'weight',
      payload: decodeJson(row['payload_json'] as String? ?? '{}'),
      source: row['source'] as String? ?? 'manual',
      measuredAt: _asInt(row['measured_at']) ?? 0,
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
      version: _asInt(row['version']) ?? 0,
      isDirty: _asInt(row['is_dirty']) ?? 1,
      syncAt: _asInt(row['sync_at']) ?? 0,
    );
  }

  Map<String, Object?> toRow() {
    return {
      'user_id': userId,
      if (clientId != null) 'client_id': clientId,
      'type': type,
      'payload_json': jsonEncode(payload),
      'source': source,
      'measured_at': measuredAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'version': version,
      'is_dirty': isDirty,
      'sync_at': syncAt,
    };
  }
}

class HealthTrendAlert {
  const HealthTrendAlert({
    required this.type,
    required this.title,
    required this.message,
    required this.isCritical,
    required this.retestAfter,
  });

  final String type;
  final String title;
  final String message;
  final bool isCritical;
  final Duration retestAfter;
}

class HealthReportRecord {
  const HealthReportRecord({
    this.id,
    this.userId = kLocalUserId,
    required this.clientId,
    required this.imagePath,
    required this.reportTime,
    required this.summary,
    required this.rawText,
    required this.structured,
    required this.provider,
    required this.createdAt,
    required this.updatedAt,
    this.version = 0,
    this.isDirty = 1,
    this.syncAt = 0,
  });

  final int? id;
  final String userId;
  final String clientId;
  final String imagePath;
  final int reportTime;
  final String summary;
  final String rawText;
  final Map<String, dynamic> structured;
  final String provider;
  final int createdAt;
  final int updatedAt;
  final int version;
  final int isDirty;
  final int syncAt;

  DateTime get reportDateTime =>
      DateTime.fromMillisecondsSinceEpoch(reportTime);
  DateTime get createdTime => DateTime.fromMillisecondsSinceEpoch(createdAt);

  int get indicatorCount => (structured['indicators'] as List?)?.length ?? 0;

  factory HealthReportRecord.fromRow(Map<String, Object?> row) {
    return HealthReportRecord(
      id: _asInt(row['id']),
      userId: row['user_id'] as String? ?? kLocalUserId,
      clientId: row['client_id'] as String? ?? '',
      imagePath: row['image_path'] as String? ?? '',
      reportTime: _asInt(row['report_time']) ?? 0,
      summary: row['summary'] as String? ?? '',
      rawText: row['raw_text'] as String? ?? '',
      structured: decodeJson(row['structured_json'] as String? ?? '{}'),
      provider: row['provider'] as String? ?? '',
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
      version: _asInt(row['version']) ?? 0,
      isDirty: _asInt(row['is_dirty']) ?? 1,
      syncAt: _asInt(row['sync_at']) ?? 0,
    );
  }

  Map<String, Object?> toRow() {
    return {
      'user_id': userId,
      'client_id': clientId,
      'image_path': imagePath,
      'report_time': reportTime,
      'summary': summary,
      'raw_text': rawText,
      'structured_json': jsonEncode(structured),
      'provider': provider,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'version': version,
      'is_dirty': isDirty,
      'sync_at': syncAt,
    };
  }
}

class WeeklyHealthReportData {
  const WeeklyHealthReportData({
    this.id,
    this.userId = kLocalUserId,
    required this.clientId,
    required this.startAt,
    required this.endAt,
    required this.structured,
    required this.provider,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String userId;
  final String clientId;
  final int startAt;
  final int endAt;
  final Map<String, dynamic> structured;
  final String provider;
  final int createdAt;
  final int updatedAt;

  DateTime get startDate => DateTime.fromMillisecondsSinceEpoch(startAt);
  DateTime get endDate => DateTime.fromMillisecondsSinceEpoch(endAt);

  factory WeeklyHealthReportData.fromRow(Map<String, Object?> row) {
    return WeeklyHealthReportData(
      id: _asInt(row['id']),
      userId: row['user_id'] as String? ?? kLocalUserId,
      clientId: row['client_id'] as String? ?? '',
      startAt: _asInt(row['start_at']) ?? 0,
      endAt: _asInt(row['end_at']) ?? 0,
      structured: decodeJson(row['structured_json'] as String? ?? '{}'),
      provider: row['provider'] as String? ?? '',
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
    );
  }

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'client_id': clientId,
        'start_at': startAt,
        'end_at': endAt,
        'structured_json': jsonEncode(structured),
        'provider': provider,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

class MealFoodItem {
  const MealFoodItem({
    required this.name,
    required this.weightG,
    required this.calories,
  });

  final String name;
  final double weightG;
  final double calories;

  factory MealFoodItem.fromJson(Map<String, dynamic> json) {
    return MealFoodItem(
      name: json['name']?.toString() ?? '食材',
      weightG: _asDouble(json['weightG'] ?? json['weight'] ?? json['grams']),
      calories: _asDouble(json['calories'] ?? json['kcal']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'weightG': weightG,
        'calories': calories,
      };
}

class MealRecordData {
  const MealRecordData({
    this.id,
    this.userId = kLocalUserId,
    required this.clientId,
    required this.name,
    required this.mealType,
    required this.eatenAt,
    required this.imagePath,
    required this.totalCalories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.healthScore,
    required this.glycemicLoad,
    required this.foods,
    required this.nutrition,
    required this.createdAt,
    required this.updatedAt,
    this.portion = 1,
    this.cost = 0,
    this.diningType = 'home',
    this.merchant = '',
    this.note = '',
    this.version = 0,
    this.isDirty = 1,
    this.syncAt = 0,
  });

  final int? id;
  final String userId;
  final String clientId;
  final String name;
  final String mealType;
  final int eatenAt;
  final String imagePath;
  final double totalCalories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double healthScore;
  final double glycemicLoad;
  final List<MealFoodItem> foods;
  final Map<String, dynamic> nutrition;
  final int createdAt;
  final int updatedAt;
  final double portion;
  final double cost;
  final String diningType;
  final String merchant;
  final String note;
  final int version;
  final int isDirty;
  final int syncAt;

  DateTime get eatenTime => DateTime.fromMillisecondsSinceEpoch(eatenAt);

  String get mealLabel => switch (mealType) {
        'breakfast' => '早餐',
        'dinner' => '晚餐',
        'snack' => '加餐',
        'late_night' => '夜宵',
        _ => '午餐',
      };

  factory MealRecordData.fromRow(Map<String, Object?> row) {
    final rawFoods = jsonDecode(row['foods_json'] as String? ?? '[]');
    final foods = rawFoods is List
        ? rawFoods
            .whereType<Map>()
            .map((item) => MealFoodItem.fromJson(
                  item.map((key, value) => MapEntry('$key', value)),
                ))
            .toList()
        : <MealFoodItem>[];
    return MealRecordData(
      id: _asInt(row['id']),
      userId: row['user_id'] as String? ?? kLocalUserId,
      clientId: row['client_id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      mealType: row['meal_type'] as String? ?? 'lunch',
      eatenAt: _asInt(row['eaten_at']) ?? 0,
      imagePath: row['image_path'] as String? ?? '',
      totalCalories: _asDouble(row['total_calories']),
      proteinG: _asDouble(row['protein_g']),
      carbsG: _asDouble(row['carbs_g']),
      fatG: _asDouble(row['fat_g']),
      healthScore: _asDouble(row['health_score']),
      glycemicLoad: _asDouble(row['glycemic_load']),
      foods: foods,
      nutrition: decodeJson(row['nutrition_json'] as String? ?? '{}'),
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
      portion: _asDouble(row['portion'] ?? 1),
      cost: _asDouble(row['cost']),
      diningType: row['dining_type'] as String? ?? 'home',
      merchant: row['merchant'] as String? ?? '',
      note: row['note'] as String? ?? '',
      version: _asInt(row['version']) ?? 0,
      isDirty: _asInt(row['is_dirty']) ?? 1,
      syncAt: _asInt(row['sync_at']) ?? 0,
    );
  }

  Map<String, Object?> toRow() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'client_id': clientId,
      'name': name,
      'meal_type': mealType,
      'eaten_at': eatenAt,
      'image_path': imagePath,
      'total_calories': totalCalories,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'fat_g': fatG,
      'health_score': healthScore,
      'glycemic_load': glycemicLoad,
      'foods_json': jsonEncode(foods.map((item) => item.toJson()).toList()),
      'nutrition_json': jsonEncode(nutrition),
      'created_at': createdAt,
      'updated_at': updatedAt,
      'portion': portion,
      'cost': cost,
      'dining_type': diningType,
      'merchant': merchant,
      'note': note,
      'version': version,
      'is_dirty': isDirty,
      'sync_at': syncAt,
    };
  }

  MealRecordData copyWith({
    int? id,
    String? name,
    String? mealType,
    int? eatenAt,
    String? imagePath,
    double? totalCalories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? healthScore,
    double? glycemicLoad,
    List<MealFoodItem>? foods,
    Map<String, dynamic>? nutrition,
    int? updatedAt,
    double? portion,
    double? cost,
    String? diningType,
    String? merchant,
    String? note,
  }) {
    return MealRecordData(
      id: id ?? this.id,
      userId: userId,
      clientId: clientId,
      name: name ?? this.name,
      mealType: mealType ?? this.mealType,
      eatenAt: eatenAt ?? this.eatenAt,
      imagePath: imagePath ?? this.imagePath,
      totalCalories: totalCalories ?? this.totalCalories,
      proteinG: proteinG ?? this.proteinG,
      carbsG: carbsG ?? this.carbsG,
      fatG: fatG ?? this.fatG,
      healthScore: healthScore ?? this.healthScore,
      glycemicLoad: glycemicLoad ?? this.glycemicLoad,
      foods: foods ?? this.foods,
      nutrition: nutrition ?? this.nutrition,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      portion: portion ?? this.portion,
      cost: cost ?? this.cost,
      diningType: diningType ?? this.diningType,
      merchant: merchant ?? this.merchant,
      note: note ?? this.note,
      version: version,
      isDirty: 1,
      syncAt: syncAt,
    );
  }
}

class MealRecipeData {
  const MealRecipeData({
    this.id,
    this.userId = kLocalUserId,
    required this.clientId,
    required this.name,
    required this.category,
    required this.durationMinutes,
    required this.difficulty,
    required this.ingredients,
    required this.steps,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.isFavorite,
    required this.isCustom,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String userId;
  final String clientId;
  final String name;
  final String category;
  final int durationMinutes;
  final String difficulty;
  final List<String> ingredients;
  final List<String> steps;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final bool isFavorite;
  final bool isCustom;
  final int createdAt;
  final int updatedAt;

  factory MealRecipeData.fromRow(Map<String, Object?> row) {
    List<String> strings(String key) {
      final raw = jsonDecode(row[key] as String? ?? '[]');
      return raw is List ? raw.map((item) => '$item').toList() : const [];
    }

    return MealRecipeData(
      id: _asInt(row['id']),
      userId: row['user_id'] as String? ?? kLocalUserId,
      clientId: row['client_id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      category: row['category'] as String? ?? '家常菜',
      durationMinutes: _asInt(row['duration_minutes']) ?? 20,
      difficulty: row['difficulty'] as String? ?? '简单',
      ingredients: strings('ingredients_json'),
      steps: strings('steps_json'),
      calories: _asDouble(row['calories']),
      proteinG: _asDouble(row['protein_g']),
      carbsG: _asDouble(row['carbs_g']),
      fatG: _asDouble(row['fat_g']),
      isFavorite: _asInt(row['is_favorite']) == 1,
      isCustom: _asInt(row['is_custom']) == 1,
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
    );
  }

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'client_id': clientId,
        'name': name,
        'category': category,
        'duration_minutes': durationMinutes,
        'difficulty': difficulty,
        'ingredients_json': jsonEncode(ingredients),
        'steps_json': jsonEncode(steps),
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'is_favorite': isFavorite ? 1 : 0,
        'is_custom': isCustom ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  MealRecipeData copyWith({
    int? id,
    bool? isFavorite,
    int? updatedAt,
  }) {
    return MealRecipeData(
      id: id ?? this.id,
      userId: userId,
      clientId: clientId,
      name: name,
      category: category,
      durationMinutes: durationMinutes,
      difficulty: difficulty,
      ingredients: ingredients,
      steps: steps,
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      isFavorite: isFavorite ?? this.isFavorite,
      isCustom: isCustom,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DailyNutritionTargets {
  const DailyNutritionTargets({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  factory DailyNutritionTargets.fromProfile(UserProfileData? profile) {
    final p = profile ?? UserProfileData.empty();
    if (!p.isComplete) {
      return const DailyNutritionTargets(
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
      );
    }
    final weight = p.weightKg;
    final height = p.heightCm;
    final age = p.age;
    final isMale = p.gender == 'male';
    final bmr = isMale
        ? 10 * weight + 6.25 * height - 5 * age + 5
        : 10 * weight + 6.25 * height - 5 * age - 161;
    final activity = switch (p.exerciseBase) {
      'moderate' => 1.55,
      'light' => 1.375,
      _ => 1.2,
    };
    final tdee = bmr * activity;
    final calories = switch (p.goal) {
      'fat_loss' => (tdee - 400).clamp(1200, 3000).toDouble(),
      'glucose_control' ||
      'bp_control' =>
        (tdee - 200).clamp(1200, 3000).toDouble(),
      _ => tdee.clamp(1200, 3000).toDouble(),
    };
    final protein =
        (weight * (p.goal == 'fat_loss' ? 1.6 : 1.2)).clamp(50, 180);
    final fat = (calories * 0.25 / 9).clamp(30, 90);
    final carbs = ((calories - protein * 4 - fat * 9) / 4).clamp(100, 380);
    return DailyNutritionTargets(
      calories: calories,
      proteinG: protein.toDouble(),
      carbsG: carbs.toDouble(),
      fatG: fat.toDouble(),
    );
  }
}

class PlanRecordData {
  const PlanRecordData({
    this.id,
    this.userId = kLocalUserId,
    required this.type,
    required this.planDate,
    required this.payload,
    required this.aiProvider,
    required this.aiModel,
    required this.createdAt,
    required this.updatedAt,
    this.version = 0,
    this.isDirty = 1,
  });

  final int? id;
  final String userId;
  final String type;
  final int planDate;
  final Map<String, dynamic> payload;
  final String aiProvider;
  final String aiModel;
  final int createdAt;
  final int updatedAt;
  final int version;
  final int isDirty;

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(planDate);

  String get label {
    return switch (type) {
      'meal' => '定制菜单',
      'exercise' => '运动计划',
      'medicine' => '用药提醒',
      _ => '健康计划',
    };
  }

  String get summary => payload['summary']?.toString() ?? '';

  factory PlanRecordData.fromRow(Map<String, Object?> row) {
    return PlanRecordData(
      id: _asInt(row['id']),
      userId: row['user_id'] as String? ?? kLocalUserId,
      type: row['type'] as String? ?? 'meal',
      planDate: _asInt(row['plan_date']) ?? 0,
      payload: decodeJson(row['payload_json'] as String? ?? '{}'),
      aiProvider: row['ai_provider'] as String? ?? 'local',
      aiModel: row['ai_model'] as String? ?? 'rules-v1',
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
      version: _asInt(row['version']) ?? 0,
      isDirty: _asInt(row['is_dirty']) ?? 1,
    );
  }

  Map<String, Object?> toRow() {
    return {
      'user_id': userId,
      'type': type,
      'plan_date': planDate,
      'payload_json': jsonEncode(payload),
      'ai_provider': aiProvider,
      'ai_model': aiModel,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'version': version,
      'is_dirty': isDirty,
    };
  }
}

class ClockRecordData {
  const ClockRecordData({
    this.id,
    this.userId = kLocalUserId,
    required this.type,
    required this.status,
    required this.clockAt,
    required this.note,
    required this.photoPath,
    required this.createdAt,
    required this.updatedAt,
    this.version = 0,
    this.isDirty = 1,
  });

  final int? id;
  final String userId;
  final String type;
  final String status;
  final int clockAt;
  final String note;
  final String photoPath;
  final int createdAt;
  final int updatedAt;
  final int version;
  final int isDirty;

  DateTime get clockTime => DateTime.fromMillisecondsSinceEpoch(clockAt);

  String get label {
    return switch (type) {
      'meal' => '饮食',
      'exercise' => '运动',
      'medicine' => '用药',
      'weight' => '称重',
      'water' => '饮水',
      'quit_smoking' => '戒烟',
      _ => '打卡',
    };
  }

  factory ClockRecordData.fromRow(Map<String, Object?> row) {
    return ClockRecordData(
      id: _asInt(row['id']),
      userId: row['user_id'] as String? ?? kLocalUserId,
      type: row['type'] as String? ?? 'meal',
      status: row['status'] as String? ?? 'done',
      clockAt: _asInt(row['clock_at']) ?? 0,
      note: row['note'] as String? ?? '',
      photoPath: row['photo_path'] as String? ?? '',
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
      version: _asInt(row['version']) ?? 0,
      isDirty: _asInt(row['is_dirty']) ?? 1,
    );
  }

  Map<String, Object?> toRow() {
    return {
      'user_id': userId,
      'type': type,
      'status': status,
      'clock_at': clockAt,
      'note': note,
      'photo_path': photoPath,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'version': version,
      'is_dirty': isDirty,
    };
  }
}

class TimeOfDayValue {
  const TimeOfDayValue({required this.hour, required this.minute});

  final int hour;
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is TimeOfDayValue && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

class ReminderData {
  const ReminderData({
    this.id,
    this.userId = kLocalUserId,
    required this.type,
    required this.remindAt,
    required this.payload,
    required this.channel,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.version = 0,
    this.isDirty = 1,
  });

  final int? id;
  final String userId;
  final String type;
  final int remindAt;
  final Map<String, dynamic> payload;
  final String channel;
  final String status;
  final int createdAt;
  final int updatedAt;
  final int version;
  final int isDirty;

  DateTime get remindTime => DateTime.fromMillisecondsSinceEpoch(remindAt);

  bool get isArchived => payload['archived'] == true;

  bool get isEnabled => status != 'paused' && !isArchived;

  String get source => channel == 'local' ? 'manual' : channel;

  bool get isWeekly => channel == 'local' && payload['scheduleMode'] != 'once';

  String get displayLabel {
    final medicineName = payload['medicineName']?.toString().trim() ?? '';
    return type == 'medicine' && medicineName.isNotEmpty ? medicineName : label;
  }

  List<TimeOfDayValue> get dailyTimes {
    final raw = payload['dailyTimes'];
    if (raw is List) {
      final values = raw
          .whereType<Map>()
          .map((item) {
            final hour = (item['hour'] as num?)?.toInt();
            final minute = (item['minute'] as num?)?.toInt();
            if (hour == null || minute == null) return null;
            if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
            return TimeOfDayValue(hour: hour, minute: minute);
          })
          .whereType<TimeOfDayValue>()
          .toSet()
          .toList()
        ..sort((a, b) =>
            (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      if (values.isNotEmpty) return values;
    }
    return [TimeOfDayValue(hour: remindTime.hour, minute: remindTime.minute)];
  }

  String doseAt(TimeOfDayValue time) {
    final values = payload['doseByTime'];
    final value =
        values is Map ? values[_timeKey(time)]?.toString().trim() : '';
    return value?.isNotEmpty == true
        ? value!
        : payload['dose']?.toString().trim() ?? '';
  }

  String instructionsAt(TimeOfDayValue time) {
    final values = payload['instructionsByTime'];
    final value =
        values is Map ? values[_timeKey(time)]?.toString().trim() : '';
    return value?.isNotEmpty == true
        ? value!
        : payload['instructions']?.toString().trim() ?? '';
  }

  DateTime? get courseEndDate {
    final value = payload['courseEndAt'];
    if (value is! num) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime(date.year, date.month, date.day);
  }

  double? get inventoryRemaining =>
      (payload['inventoryRemaining'] as num?)?.toDouble();

  double? get refillThreshold =>
      (payload['refillThreshold'] as num?)?.toDouble();

  bool get refillNeeded {
    final remaining = inventoryRemaining;
    final threshold = refillThreshold;
    return remaining != null && threshold != null && remaining <= threshold;
  }

  String? actionAt(DateTime occurrence) {
    final history = payload['actionHistory'];
    if (history is! Map) return null;
    return history[_occurrenceKey(occurrence)]?.toString();
  }

  bool acknowledgedAt(DateTime occurrence) {
    final history = payload['ackHistory'];
    return history is Map && history[_occurrenceKey(occurrence)] == true;
  }

  List<int> get weekdays {
    if (!isWeekly) return const [];
    final raw = payload['weekdays'];
    if (raw is! List) return const [1, 2, 3, 4, 5, 6, 7];
    final values = raw
        .whereType<num>()
        .map((value) => value.toInt())
        .where((value) => value >= 1 && value <= 7)
        .toSet()
        .toList()
      ..sort();
    return values.isEmpty ? const [1, 2, 3, 4, 5, 6, 7] : values;
  }

  DateTime get startDate {
    final raw = payload['startDate'];
    final value = raw is num ? raw.toInt() : null;
    final date =
        value == null ? remindTime : DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime(date.year, date.month, date.day);
  }

  bool occursOn(DateTime date) {
    if (isArchived) return false;
    final day = DateTime(date.year, date.month, date.day);
    final courseEnd = courseEndDate;
    if (courseEnd != null && day.isAfter(courseEnd)) return false;
    if (!isWeekly) {
      final reminderDay = DateTime(
        remindTime.year,
        remindTime.month,
        remindTime.day,
      );
      return reminderDay == day;
    }
    return !day.isBefore(startDate) && weekdays.contains(day.weekday);
  }

  DateTime? nextOccurrence(DateTime after) {
    if (!isWeekly) return remindTime.isAfter(after) ? remindTime : null;
    final afterDay = DateTime(after.year, after.month, after.day);
    final firstDay = startDate.isAfter(afterDay) ? startDate : afterDay;
    for (var offset = 0; offset < 14; offset++) {
      final day = firstDay.add(Duration(days: offset));
      if (!occursOn(day)) continue;
      final candidate = DateTime(
        day.year,
        day.month,
        day.day,
        remindTime.hour,
        remindTime.minute,
      );
      if (candidate.isAfter(after)) return candidate;
    }
    return null;
  }

  String get label {
    return switch (type) {
      'meal' => '饮食提醒',
      'exercise' => '运动提醒',
      'medicine' => '用药提醒',
      'weight' => '称重提醒',
      'water' => '饮水提醒',
      'quit_smoking' => '戒烟提醒',
      'bp' => '血压提醒',
      'glucose' => '血糖提醒',
      _ => '提醒',
    };
  }

  String get timeText {
    final hour = remindTime.hour.toString().padLeft(2, '0');
    final minute = remindTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  factory ReminderData.fromRow(Map<String, Object?> row) {
    return ReminderData(
      id: _asInt(row['id']),
      userId: row['user_id'] as String? ?? kLocalUserId,
      type: row['type'] as String? ?? 'meal',
      remindAt: _asInt(row['remind_at']) ?? 0,
      payload: decodeJson(row['payload_json'] as String? ?? '{}'),
      channel: row['channel'] as String? ?? 'local',
      status: row['status'] as String? ?? 'pending',
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
      version: _asInt(row['version']) ?? 0,
      isDirty: _asInt(row['is_dirty']) ?? 1,
    );
  }

  Map<String, Object?> toRow() {
    return {
      'user_id': userId,
      'type': type,
      'remind_at': remindAt,
      'payload_json': jsonEncode(payload),
      'channel': channel,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'version': version,
      'is_dirty': isDirty,
    };
  }
}

String _timeKey(TimeOfDayValue time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

class HealthDashboardData {
  const HealthDashboardData({
    required this.profile,
    required this.indicators,
    required this.plans,
    required this.clockRecords,
    required this.reminders,
  });

  final UserProfileData? profile;
  final List<HealthIndicatorEntry> indicators;
  final List<PlanRecordData> plans;
  final List<ClockRecordData> clockRecords;
  final List<ReminderData> reminders;

  HealthIndicatorEntry? latestIndicator(String type) {
    for (final item in indicators) {
      if (item.type == type) return item;
    }
    return null;
  }

  int get todayClockCount {
    final now = DateTime.now();
    return clockRecords.where((item) {
      final t = item.clockTime;
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).length;
  }

  double get todayCompletion {
    final now = DateTime.now();
    final completedTypes = clockRecords
        .where((item) {
          final time = item.clockTime;
          return item.status == 'done' &&
              time.year == now.year &&
              time.month == now.month &&
              time.day == now.day;
        })
        .map((item) => item.type)
        .where({
          'meal',
          'exercise',
          'medicine',
          'weight',
          'water',
          'quit_smoking'
        }.contains)
        .toSet();
    return (completedTypes.length / 4).clamp(0, 1).toDouble();
  }

  List<double> weightTrend({int limit = 8}) {
    return indicators
        .where((item) => item.type == 'weight')
        .take(limit)
        .map((item) => item.numericTrendValue)
        .whereType<double>()
        .toList()
        .reversed
        .toList();
  }
}

class ClockStats {
  const ClockStats({
    required this.today,
    required this.week,
    required this.month,
    required this.todayDays,
    required this.weekDays,
    required this.monthDays,
  });

  final Map<String, int> today;
  final Map<String, int> week;
  final Map<String, int> month;
  final int todayDays;
  final int weekDays;
  final int monthDays;

  static const List<String> allTypes = [
    'meal',
    'exercise',
    'medicine',
    'weight',
    'water'
  ];
  static const int dailyTarget = 4; // meal + exercise + medicine + weight

  double rateForPeriod(Map<String, int> counts, int days) {
    final total = allTypes.fold(0, (sum, t) => sum + (counts[t] ?? 0));
    final expected = dailyTarget * days;
    if (expected == 0) return 0;
    return (total / expected).clamp(0.0, 1.0);
  }

  double get todayRate => rateForPeriod(today, todayDays);
  double get weekRate => rateForPeriod(week, weekDays);
  double get monthRate => rateForPeriod(month, monthDays);
}

Map<String, dynamic> decodeJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
  } catch (_) {
    return {};
  }
  return {};
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double _asDouble(Object? value) => _asDoubleOrNull(value) ?? 0;

double? _asDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch('$value');
  return match == null ? null : double.tryParse(match.group(0)!);
}

String _occurrenceKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _fmt(Object? value, {int digits = 0}) {
  final number = _asDoubleOrNull(value);
  if (number == null) return '--';
  return number.toStringAsFixed(digits);
}
