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
  final int version;
  final int isDirty;
  final int syncAt;

  DateTime get eatenTime => DateTime.fromMillisecondsSinceEpoch(eatenAt);

  String get mealLabel => switch (mealType) {
        'breakfast' => '早餐',
        'dinner' => '晚餐',
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
      version: version,
      isDirty: 1,
      syncAt: syncAt,
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
      'meal' => '饮食计划',
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

  String get label {
    return switch (type) {
      'meal' => '饮食提醒',
      'exercise' => '运动提醒',
      'medicine' => '用药提醒',
      'weight' => '称重提醒',
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
    return (todayClockCount / 4).clamp(0, 1).toDouble();
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

String _fmt(Object? value, {int digits = 0}) {
  final number = _asDoubleOrNull(value);
  if (number == null) return '--';
  return number.toStringAsFixed(digits);
}
