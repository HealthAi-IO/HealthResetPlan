import 'dart:math';

import 'package:flutter/foundation.dart';

import '../storage/app_database.dart';
import 'health_models.dart';

class HealthRepository extends ChangeNotifier {
  HealthRepository({required this.database});

  final AppDatabase database;
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    await database.open();
    await _seedIfEmpty();
    _ready = true;
  }

  Future<HealthDashboardData> loadDashboard() async {
    return HealthDashboardData(
      profile: await loadProfile(),
      indicators: await loadIndicators(limit: 16),
      plans: await loadPlans(limit: 18),
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

  Future<List<HealthIndicatorEntry>> loadIndicators(
      {int limit = 50, String? type}) async {
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

  Future<void> addIndicator({
    required String type,
    required Map<String, dynamic> payload,
    String source = 'manual',
    DateTime? measuredAt,
  }) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = HealthIndicatorEntry(
      type: type,
      payload: payload,
      source: source,
      measuredAt: (measuredAt ?? DateTime.now()).millisecondsSinceEpoch,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('health_indicator', entry.toRow());

    if (type == 'weight' && payload['weightKg'] is num) {
      final profile = await loadProfile();
      if (profile != null) {
        await db.update(
          'user_profile',
          profile
              .copyWith(
                weightKg: (payload['weightKg'] as num).toDouble(),
                updatedAt: now,
                isDirty: 1,
              )
              .toRow(),
          where: 'user_id = ?',
          whereArgs: [kLocalUserId],
        );
      }
    }
    notifyListeners();
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

  Future<void> generateWeeklyPlan() async {
    final db = await database.open();
    final profile = await loadProfile() ?? UserProfileData.empty();
    final indicators = await loadIndicators(limit: 8);
    final latestBp = indicators.where((item) => item.type == 'bp').firstOrNull;
    final highBp = latestBp != null &&
        (((latestBp.payload['systolic'] as num?)?.toInt() ?? 0) >= 140 ||
            ((latestBp.payload['diastolic'] as num?)?.toInt() ?? 0) >= 90);
    final bmi = profile.bmi;
    final targetKcal = bmi >= 28
        ? 1500
        : bmi >= 24
            ? 1700
            : 1900;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final createdAt = now.millisecondsSinceEpoch;
    final mealTemplates = _mealTemplates(targetKcal, highBp: highBp);
    final exerciseTemplates = _exerciseTemplates(bmi, highBp: highBp);

    await db.delete('plan', where: 'user_id = ?', whereArgs: [kLocalUserId]);
    for (var i = 0; i < 7; i++) {
      final date = today.add(Duration(days: i));
      final meal = mealTemplates[i % mealTemplates.length];
      final exercise = exerciseTemplates[i % exerciseTemplates.length];
      await db.insert(
        'plan',
        PlanRecordData(
          type: 'meal',
          planDate: date.millisecondsSinceEpoch,
          payload: meal,
          aiProvider: 'local',
          aiModel: 'rules-v1',
          createdAt: createdAt,
          updatedAt: createdAt,
        ).toRow(),
        replace: true,
      );
      await db.insert(
        'plan',
        PlanRecordData(
          type: 'exercise',
          planDate: date.millisecondsSinceEpoch,
          payload: exercise,
          aiProvider: 'local',
          aiModel: 'rules-v1',
          createdAt: createdAt,
          updatedAt: createdAt,
        ).toRow(),
        replace: true,
      );
    }

    final reminders = await loadReminders();
    if (reminders.isEmpty) {
      await _insertDefaultReminders(db, createdAt);
    }
    notifyListeners();
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

  Future<void> addClockRecord({
    required String type,
    String status = 'done',
    String note = '',
    DateTime? clockAt,
  }) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'clock_record',
      ClockRecordData(
        type: type,
        status: status,
        clockAt: (clockAt ?? DateTime.now()).millisecondsSinceEpoch,
        note: note,
        photoPath: '',
        createdAt: now,
        updatedAt: now,
      ).toRow(),
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

  Future<void> addReminder({
    required String type,
    required TimeOfDayValue time,
    String note = '',
  }) async {
    final db = await database.open();
    final now = DateTime.now();
    final remindAt =
        DateTime(now.year, now.month, now.day, time.hour, time.minute);
    final timestamp = now.millisecondsSinceEpoch;
    await db.insert(
      'reminder',
      ReminderData(
        type: type,
        remindAt: remindAt.millisecondsSinceEpoch,
        payload: {'note': note},
        channel: 'local',
        status: 'pending',
        createdAt: timestamp,
        updatedAt: timestamp,
      ).toRow(),
    );
    notifyListeners();
  }

  Future<void> deleteReminder(int id) async {
    final db = await database.open();
    await db.delete('reminder', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> resetDemoData() async {
    final db = await database.open();
    await db.transaction((txn) async {
      for (final table in [
        'user_profile',
        'health_indicator',
        'plan',
        'clock_record',
        'reminder'
      ]) {
        await txn.delete(table);
      }
    });
    await _seedIfEmpty(force: true);
    notifyListeners();
  }

  void signalChanged() => notifyListeners();

  Future<void> _seedIfEmpty({bool force = false}) async {
    final db = await database.open();
    final count = await db.count('user_profile');
    if (!force && count > 0) return;

    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final timestamp = now.millisecondsSinceEpoch;

    await db.insert(
      'user_profile',
      UserProfileData(
        nickname: '本地用户',
        gender: 'female',
        birthYear: 1988,
        heightCm: 168,
        weightKg: 74.5,
        medicalHistory: '血压偏高，近期关注体重管理',
        medications: '按医嘱记录用药，未填写具体药物',
        createdAt: timestamp,
        updatedAt: timestamp,
      ).toRow(),
    );

    final samples = [
      HealthIndicatorEntry(
        type: 'bp',
        payload: {'systolic': 136, 'diastolic': 86},
        source: 'manual',
        measuredAt:
            midnight.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      for (var i = 6; i >= 0; i--)
        HealthIndicatorEntry(
          type: 'weight',
          payload: {'weightKg': 74.5 + i * 0.18 + Random(i).nextDouble() * 0.2},
          source: 'manual',
          measuredAt:
              midnight.subtract(Duration(days: i)).millisecondsSinceEpoch,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      HealthIndicatorEntry(
        type: 'glucose',
        payload: {'glucoseMmol': 5.8},
        source: 'report',
        measuredAt:
            midnight.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      HealthIndicatorEntry(
        type: 'lipid',
        payload: {'tc': 5.4, 'ldl': 3.4},
        source: 'report',
        measuredAt:
            midnight.subtract(const Duration(days: 4)).millisecondsSinceEpoch,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    ];
    for (final item in samples) {
      await db.insert('health_indicator', item.toRow());
    }

    for (final type in ['meal', 'exercise', 'medicine']) {
      await db.insert(
        'clock_record',
        ClockRecordData(
          type: type,
          status: 'done',
          clockAt: now
              .subtract(Duration(hours: type == 'meal' ? 2 : 5))
              .millisecondsSinceEpoch,
          note: type == 'meal' ? '午餐选择低盐高蛋白' : '',
          photoPath: '',
          createdAt: timestamp,
          updatedAt: timestamp,
        ).toRow(),
      );
    }

    await _insertDefaultReminders(db, timestamp);
    await generateWeeklyPlan();
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
          remindAt: DateTime(now.year, now.month, now.day, item.$2, item.$3)
              .millisecondsSinceEpoch,
          payload: {'note': item.$4},
          channel: 'local',
          status: 'pending',
          createdAt: timestamp,
          updatedAt: timestamp,
        ).toRow(),
      );
    }
  }

  List<Map<String, dynamic>> _mealTemplates(int targetKcal,
      {required bool highBp}) {
    final saltNote = highBp ? '低盐，全天钠摄入控制在 1500-2000mg' : '少盐少油，保持高纤维';
    return [
      {
        'summary': '$targetKcal kcal 左右，$saltNote',
        'items': ['燕麦牛奶 + 水煮蛋', '鸡胸杂粮饭 + 西兰花', '清蒸鱼 + 菌菇青菜', '无糖酸奶']
      },
      {
        'summary': '$targetKcal kcal 左右，优先优质蛋白与蔬菜',
        'items': ['全麦吐司 + 鸡蛋 + 番茄', '牛肉荞麦面 + 时蔬', '豆腐虾仁汤 + 糙米饭', '苹果半个']
      },
      {
        'summary': '$targetKcal kcal 左右，晚餐减少精制碳水',
        'items': ['杂粮粥 + 鸡蛋', '虾仁藜麦沙拉', '鸡腿肉去皮 + 大量绿叶菜', '坚果 10g']
      },
    ];
  }

  List<Map<String, dynamic>> _exerciseTemplates(double bmi,
      {required bool highBp}) {
    final intensity = highBp ? '中低强度' : '中等强度';
    final minutes = bmi >= 28 ? 35 : 30;
    return [
      {
        'summary': '$intensity 有氧 $minutes 分钟，避免突然冲刺',
        'items': ['热身 5 分钟', '快走或椭圆机 $minutes 分钟', '拉伸 8 分钟']
      },
      {
        'summary': '力量训练 25 分钟，重点保护膝踝',
        'items': ['深蹲辅助 3 组', '弹力带划船 3 组', '靠墙俯卧撑 3 组', '核心稳定 8 分钟']
      },
      {
        'summary': '主动恢复日，保持活动量',
        'items': ['餐后步行 15 分钟', '肩颈放松 10 分钟', '睡前呼吸训练 5 分钟']
      },
    ];
  }
}

class TimeOfDayValue {
  const TimeOfDayValue({required this.hour, required this.minute});

  final int hour;
  final int minute;
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
