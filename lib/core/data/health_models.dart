import 'dart:convert';

const String kLocalUserId = 'local-user';

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
  final int version;
  final int isDirty;

  int get age {
    if (birthYear <= 1900) return 0;
    return DateTime.now().year - birthYear;
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
      nickname.isNotEmpty && heightCm > 0 && weightKg > 0 && birthYear > 0;

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
      'version': version,
      'is_dirty': isDirty,
    };
  }
}

class HealthIndicatorEntry {
  const HealthIndicatorEntry({
    this.id,
    this.userId = kLocalUserId,
    required this.type,
    required this.payload,
    required this.source,
    required this.measuredAt,
    required this.createdAt,
    required this.updatedAt,
    this.version = 0,
    this.isDirty = 1,
  });

  final int? id;
  final String userId;
  final String type;
  final Map<String, dynamic> payload;
  final String source;
  final int measuredAt;
  final int createdAt;
  final int updatedAt;
  final int version;
  final int isDirty;

  DateTime get measuredTime => DateTime.fromMillisecondsSinceEpoch(measuredAt);

  String get label {
    return switch (type) {
      'bp' => '血压',
      'weight' => '体重',
      'glucose' => '血糖',
      'lipid' => '血脂',
      'heart_rate' => '心率',
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
      _ => payload.values.map((e) => '$e').join(' / '),
    };
  }

  double? get numericTrendValue {
    return switch (type) {
      'weight' => _asDoubleOrNull(payload['weightKg']),
      'bp' => _asDoubleOrNull(payload['systolic']),
      'glucose' => _asDoubleOrNull(payload['glucoseMmol']),
      'heart_rate' => _asDoubleOrNull(payload['bpm']),
      _ => null,
    };
  }

  factory HealthIndicatorEntry.fromRow(Map<String, Object?> row) {
    return HealthIndicatorEntry(
      id: _asInt(row['id']),
      userId: row['user_id'] as String? ?? kLocalUserId,
      type: row['type'] as String? ?? 'weight',
      payload: decodeJson(row['payload_json'] as String? ?? '{}'),
      source: row['source'] as String? ?? 'manual',
      measuredAt: _asInt(row['measured_at']) ?? 0,
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
      'payload_json': jsonEncode(payload),
      'source': source,
      'measured_at': measuredAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'version': version,
      'is_dirty': isDirty,
    };
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

  String get summary => payload['summary'] as String? ?? '';

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
  return double.tryParse('$value');
}

String _fmt(Object? value, {int digits = 0}) {
  final number = _asDoubleOrNull(value);
  if (number == null) return '--';
  return number.toStringAsFixed(digits);
}
