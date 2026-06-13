import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../storage/app_database.dart';
import 'health_models.dart';

class HealthRepository extends ChangeNotifier {
  HealthRepository({required this.database});

  final AppDatabase database;
  bool _ready = false;
  static const _uuid = Uuid();

  Future<void> initialize() async {
    if (_ready) return;
    await database.open();
    await _seedIfEmpty();
    _ready = true;
  }

  Future<HealthDashboardData> loadDashboard() async {
    // 每种指标类型各取最新 5 条，确保「今日数据」每类都能找到最新值
    const types = ['weight', 'bp', 'glucose', 'heart_rate', 'lipid', 'bmi'];
    final perType = await Future.wait(
      types.map((t) => loadIndicators(type: t, limit: 5)),
    );
    final indicators = [
      for (final list in perType) ...list,
    ]..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));

    return HealthDashboardData(
      profile: await loadProfile(),
      indicators: indicators,
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

  Future<void> addIndicator({
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
    await db.insert('health_indicator', entry.toRow());

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
      risks.add(mealType == 'postmeal'
          ? '餐后血糖达糖尿病标准（≥ 11.1 mmol/L，ADA 2024，建议就医）'
          : '空腹血糖达糖尿病标准（≥ 7.0 mmol/L，ADA 2024，建议就医）');
    }
    if (borderlineGlucose) {
      risks.add(mealType == 'postmeal'
          ? '餐后血糖偏高（7.8-11.0 mmol/L，糖耐量异常 IGT）'
          : '空腹血糖处于糖尿病前期（5.6-6.9 mmol/L，ADA 标准）');
    }
    if (highLipid) {
      risks.add('血脂明显偏高（TC ≥ 6.22 或 LDL ≥ 4.14 mmol/L，ACC/AHA 高危阈值）');
    }
    if (borderlineLipid) {
      risks.add('血脂处于边界高值（TC 5.18-6.21 或 LDL 3.37-4.13 mmol/L）');
    }
    if (lowHdl) {
      risks
          .add('HDL 胆固醇偏低（${isMale ? "男 < 1.04" : "女 < 1.30"} mmol/L，心血管保护不足）');
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
          '体脂率偏高（${bodyFatPct.toStringAsFixed(1)}%，${isMale ? "男 ≥ 25%" : "女 ≥ 32%"}，ACSM 标准）');
    }
    if (highWaist) {
      risks.add(
          '腰围超标（${waistCm.toStringAsFixed(1)} cm，${isMale ? "男 ≥ 90 cm" : "女 ≥ 80 cm"}，IDF 亚洲标准）');
    }
    if (dangerSpo2) {
      risks.add('血氧饱和度危险偏低（$spo2%，< 90%，建议立即就医）');
    }
    if (lowSpo2) {
      risks.add('血氧饱和度偏低（$spo2%，正常 ≥ 95%，WHO 标准）');
    }
    if (shortSleep) {
      risks.add(
          '睡眠严重不足（${sleepHours.toStringAsFixed(1)} h < 6 h，成人建议 7-9 h，NSF 标准）');
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
      if (fatNote.isNotEmpty) fatNote
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
      highBp: highBp, borderlineBp: borderlineBp, crisisBp: crisisBp,
      highGlucose: highGlucose, borderlineGlucose: borderlineGlucose,
      highLipid: highLipid, borderlineLipid: borderlineLipid,
      lowHdl: lowHdl, highTg: highTg,
      obese: obese,
      highBodyFat: highBodyFat, highWaist: highWaist,
      lowSpo2: lowSpo2, dangerSpo2: dangerSpo2,
      shortSleep: shortSleep,
      lowSteps: lowSteps,
      targetKcal: targetKcal, bmr: bmr,
      goalNote: goalNote, dietNote: dietNote,
      // 实际数值，用于生成个性化摘要
      systolic: systolic, diastolic: diastolic,
      glucoseMmol: glucoseMmol,
      tc: tc, ldl: ldl,
      bmi: bmi,
      steps: steps,
      spo2: spo2,
    );
  }

  // 仅重新计算风险，更新 DB 里的 risk 记录，不 notifyListeners（防止循环触发）
  Future<void> recalculateRisk() async {
    final db = await database.open();
    final profile = await loadProfile() ?? UserProfileData.empty();
    final r = await _assessRisk(profile);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final ts = now.millisecondsSinceEpoch;

    await db.delete('plan',
        where: "user_id = ? AND type = 'risk'", whereArgs: [kLocalUserId]);
    await db.insert(
      'plan',
      PlanRecordData(
        type: 'risk',
        planDate: today.millisecondsSinceEpoch,
        payload: r.toPayload(),
        aiProvider: 'local',
        aiModel: 'rules-v2',
        createdAt: ts,
        updatedAt: ts,
      ).toRow(),
    );
    // 不调用 notifyListeners，由调用方决定是否刷新 UI
  }

  Future<void> generateWeeklyPlan() async {
    final db = await database.open();
    final profile = await loadProfile() ?? UserProfileData.empty();
    final r = await _assessRisk(profile);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final createdAt = now.millisecondsSinceEpoch;

    final mealPlans = _buildMealTemplates(
      targetKcal: r.targetKcal,
      dietPreference: profile.dietPreference,
      goal: profile.goal,
      highBp: r.highBp || r.borderlineBp,
      highGlucose: r.highGlucose || r.borderlineGlucose,
      highLipid: r.highLipid || r.borderlineLipid,
      dietNote: r.dietNote,
      goalNote: r.goalNote,
    );
    final exercisePlans = _buildExerciseTemplates(
      exerciseBase: profile.exerciseBase,
      highBp: r.highBp,
      obese: r.obese,
      goal: profile.goal,
    );
    final measurementPlan = _buildMeasurementPlan(
      highBp: r.highBp || r.borderlineBp,
      highGlucose: r.highGlucose || r.borderlineGlucose,
      goal: profile.goal,
    );

    await db.delete('plan', where: 'user_id = ?', whereArgs: [kLocalUserId]);

    for (var i = 0; i < 7; i++) {
      final date = today.add(Duration(days: i));
      final ms = date.millisecondsSinceEpoch;
      for (final entry in [
        ('meal', mealPlans[i]),
        ('exercise', exercisePlans[i]),
        ('measurement', measurementPlan),
      ]) {
        await db.insert(
          'plan',
          PlanRecordData(
            type: entry.$1,
            planDate: ms,
            payload: entry.$2,
            aiProvider: 'local',
            aiModel: 'rules-v2',
            createdAt: createdAt,
            updatedAt: createdAt,
          ).toRow(),
          replace: true,
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
            remindAt: DateTime(now.year, now.month, now.day, 19, 0)
                .millisecondsSinceEpoch,
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
            remindAt: DateTime(now.year, now.month, now.day, 9, 30)
                .millisecondsSinceEpoch,
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

  Future<void> applyAiPlan({
    required Map<String, dynamic> plan,
    required String provider,
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
    final profile = await loadProfile() ?? UserProfileData.empty();
    final risk = await _assessRisk(profile);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final timestamp = now.millisecondsSinceEpoch;
    final keyFocus = _aiText(plan['keyFocus']);
    final targetCalories = _aiNumber(plan['targetCalories'])?.round();

    await db.transaction((txn) async {
      await txn.delete('plan', where: 'user_id = ?', whereArgs: [kLocalUserId]);

      for (var i = 0; i < days.length && i < 7; i++) {
        final day = days[i];
        final date = today.add(Duration(days: i));
        final planDate = date.millisecondsSinceEpoch;
        final diet = _aiMap(day['diet']);
        final exercise = _aiMap(day['exercise']);
        final reminders = _aiStringList(day['reminders']);

        await txn.insert(
          'plan',
          PlanRecordData(
            type: 'meal',
            planDate: planDate,
            payload: _aiMealPayload(
              diet,
              keyFocus: keyFocus,
              targetCalories: targetCalories,
            ),
            aiProvider: provider,
            aiModel: 'ai-plan-json',
            createdAt: timestamp,
            updatedAt: timestamp,
            version: 1,
            isDirty: 1,
          ).toRow(),
          replace: true,
        );

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

        await txn.insert(
          'plan',
          PlanRecordData(
            type: 'measurement',
            planDate: planDate,
            payload: _aiMeasurementPayload(reminders),
            aiProvider: provider,
            aiModel: 'ai-plan-json',
            createdAt: timestamp,
            updatedAt: timestamp,
            version: 1,
            isDirty: 1,
          ).toRow(),
          replace: true,
        );
      }

      await txn.insert(
        'plan',
        PlanRecordData(
          type: 'risk',
          planDate: today.millisecondsSinceEpoch,
          payload: {
            ...risk.toPayload(),
            if (_aiText(plan['summary']).isNotEmpty)
              'aiSummary': _aiText(plan['summary']),
            if (keyFocus.isNotEmpty) 'keyFocus': keyFocus,
            if (_aiText(plan['riskAlert']).isNotEmpty &&
                _aiText(plan['riskAlert']).toLowerCase() != 'null')
              'aiRiskAlert': _aiText(plan['riskAlert']),
          },
          aiProvider: provider,
          aiModel: 'ai-plan-json',
          createdAt: timestamp,
          updatedAt: timestamp,
          version: 1,
          isDirty: 1,
        ).toRow(),
        replace: true,
      );
    });

    notifyListeners();
  }

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
    final type = _aiText(exercise['type']);
    final duration = _aiNumber(exercise['durationMinutes'])?.round();
    final intensity = _aiText(exercise['intensity']);
    final description = _aiText(exercise['description']);
    final summaryParts = [
      if (type.isNotEmpty) type,
      if (duration != null && duration > 0) '$duration 分钟',
      if (intensity.isNotEmpty) intensity,
    ];

    return {
      'summary': summaryParts.isNotEmpty
          ? summaryParts.join(' · ')
          : (description.isNotEmpty ? description : '按 AI 建议完成今日运动'),
      if (type.isNotEmpty) 'type': type,
      if (duration != null) 'duration': duration,
      if (duration != null) 'durationMinutes': duration,
      if (intensity.isNotEmpty) 'intensity': intensity,
      if (description.isNotEmpty) 'desc': description,
      'items': [
        if (description.isNotEmpty) description,
      ],
    };
  }

  Map<String, dynamic> _aiMeasurementPayload(List<String> reminders) {
    final items =
        reminders.isEmpty ? const ['晨起空腹体重', '按需记录血压、血糖或今日不适'] : reminders;
    return {
      'summary': '今日 ${items.length} 项提醒',
      'items': items,
    };
  }

  Map<String, dynamic> _aiMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((key, value) => MapEntry('$key', value));
    return <String, dynamic>{};
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
    final rows = await db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (rows.isNotEmpty) {
      await _queueDelete(db, table, rows.first);
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
      {
        'payload_json': jsonEncode(payload),
        'updated_at': now,
        'is_dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
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
    final weekStart =
        todayStart.subtract(Duration(days: todayStart.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    Future<Map<String, int>> countByType(DateTime start, DateTime end) async {
      final rows = await db.query(
        'clock_record',
        where: 'user_id = ? AND clock_at >= ? AND clock_at < ? AND status = ?',
        whereArgs: [
          kLocalUserId,
          start.millisecondsSinceEpoch,
          end.millisecondsSinceEpoch,
          'done'
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

  // ── 数据导出 ─────────────────────────────────────────────────────

  /// 全量 JSON 备份，包含档案/指标/提醒/打卡记录
  Future<Map<String, dynamic>> exportJson() async {
    final db = await database.open();
    final profileRows = await db
        .query('user_profile', where: 'user_id = ?', whereArgs: [kLocalUserId]);
    final indicatorRows = await db.query('health_indicator',
        where: 'user_id = ?', whereArgs: [kLocalUserId]);
    final reminderRows = await db
        .query('reminder', where: 'user_id = ?', whereArgs: [kLocalUserId]);
    final clockRows = await db
        .query('clock_record', where: 'user_id = ?', whereArgs: [kLocalUserId]);
    return {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'data': {
        'userProfile': profileRows,
        'indicators': indicatorRows,
        'reminders': reminderRows,
        'clockRecords': clockRows,
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
            _ => '随机'
          };
          buf.writeln(
              '$date,$time,血糖,${e.payload['glucoseMmol'] ?? ''},mmol/L,$mt');
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
            _ => '差'
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
      await txn.delete('health_indicator',
          where: 'user_id = ?', whereArgs: [kLocalUserId]);
      await txn
          .delete('reminder', where: 'user_id = ?', whereArgs: [kLocalUserId]);
      await txn.delete('clock_record',
          where: 'user_id = ?', whereArgs: [kLocalUserId]);

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

      // 导入档案（合并：有则更新，无则插入）
      final profileList = exportData['userProfile'] as List?;
      if (profileList != null && profileList.isNotEmpty) {
        final profileMap = Map<String, Object?>.from(profileList.first as Map);
        profileMap['user_id'] = kLocalUserId;
        profileMap.remove('id');
        profileMap['updated_at'] = DateTime.now().millisecondsSinceEpoch;
        final existing = await txn.query('user_profile',
            where: 'user_id = ?', whereArgs: [kLocalUserId]);
        if (existing.isEmpty) {
          await txn.insert('user_profile', profileMap);
        } else {
          await txn.update('user_profile', profileMap,
              where: 'user_id = ?', whereArgs: [kLocalUserId]);
        }
      }
    });

    notifyListeners();
    return indicatorCount;
  }

  Future<void> _seedIfEmpty({bool force = false}) async {
    final db = await database.open();
    final count = await db.count('user_profile');
    if (!force && count > 0) return;

    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final timestamp = now.millisecondsSinceEpoch;

    // ── 国际标准参考值档案 ──────────────────────────────────────
    // 身高 175 cm，体重 70.0 kg → BMI 22.9（WHO 正常范围 18.5–24.9）
    await db.insert(
      'user_profile',
      UserProfileData(
        nickname: '演示用户',
        gender: 'male',
        birthYear: 1985, // 约 41 岁
        heightCm: 175,
        weightKg: 70.0,
        medicalHistory: '各项指标处于正常参考范围，定期监测维持健康状态',
        medications: '暂无长期用药',
        createdAt: timestamp,
        updatedAt: timestamp,
      ).toRow(),
    );

    // ── 7 天血压趋势（正常范围：收缩压 < 120 且舒张压 < 80，ACC/AHA 2017） ──
    // 注意：舒张压 = 80 即触发 Stage 1，故示例值全部 < 80
    final bpReadings = [
      (116, 74), // 6天前
      (114, 73), // 5天前
      (117, 75), // 4天前
      (115, 74), // 3天前
      (118, 76), // 2天前
      (115, 75), // 昨天
      (116, 75), // 今天（正常范围内）
    ];

    // ── 7 天体重趋势（BMI 22.9，每日自然波动 ±0.3 kg） ───────────
    final weightReadings = [70.4, 70.2, 70.5, 70.1, 70.3, 70.0, 70.0];

    final samples = [
      for (var i = 0; i < 7; i++) ...[
        HealthIndicatorEntry(
          type: 'bp',
          payload: {
            'systolic': bpReadings[i].$1,
            'diastolic': bpReadings[i].$2,
            'heartRate': 68 + (i % 3), // 心率 68–70 bpm（正常静息心率）
          },
          source: 'manual',
          measuredAt:
              midnight.subtract(Duration(days: 6 - i)).millisecondsSinceEpoch,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
        HealthIndicatorEntry(
          type: 'weight',
          payload: {'weightKg': weightReadings[i]},
          source: 'manual',
          measuredAt:
              midnight.subtract(Duration(days: 6 - i)).millisecondsSinceEpoch,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      // 空腹血糖：5.0 mmol/L（正常；ADA 糖前期起点为 5.6，故示例取 5.0）
      HealthIndicatorEntry(
        type: 'glucose',
        payload: {'glucoseMmol': 5.0, 'mealType': 'fasting'},
        source: 'report',
        measuredAt:
            midnight.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      // 血脂四项（NCEP ATP III，均低于边界高值阈值）
      //   TC  4.8 mmol/L（< 5.18 合适值，阈值以内）
      //   LDL 2.8 mmol/L（< 3.37 近优值，阈值以内）
      //   HDL 1.4 mmol/L（> 1.30 对男女均安全）
      //   TG  1.3 mmol/L（< 2.26 正常）
      HealthIndicatorEntry(
        type: 'lipid',
        payload: {'tc': 4.8, 'ldl': 2.8, 'hdl': 1.4, 'tg': 1.3},
        source: 'report',
        measuredAt:
            midnight.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      // 血氧：98%（正常 95–100%）
      HealthIndicatorEntry(
        type: 'spo2',
        payload: {'spo2Pct': 98},
        source: 'manual',
        measuredAt:
            midnight.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      // 昨日步数：8000 步（WHO 推荐目标 ≥ 10000 步）
      HealthIndicatorEntry(
        type: 'steps',
        payload: {'steps': 8000},
        source: 'manual',
        measuredAt:
            midnight.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
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
            '黄豆 + 豆腐'
          ]
        : [
            '鸡胸肉 120g',
            '清蒸鱼 150g',
            '虾仁 100g',
            '牛肉 100g',
            '三文鱼 100g',
            '鸡腿肉（去皮）130g',
            '猪瘦肉 80g'
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

    return [
      // 第1天：有氧
      {
        'summary': '$intensity 有氧 ${durations[0]} 分钟',
        'items': [
          '热身 5 分钟（原地踏步 + 肩颈活动）',
          '$cardioType ${durations[0]} 分钟',
          '整理拉伸 8 分钟'
        ],
        'type': 'cardio',
      },
      // 第2天：上肢力量
      {
        'summary': '上肢力量 ${durations[1]} 分钟（$strengthNote）',
        'items': [
          '热身 5 分钟',
          '弹力带划船 3×12',
          '俯卧撑 / 推墙 3×10',
          '哑铃弯举 3×12',
          '核心稳定 10 分钟'
        ],
        'type': 'strength',
      },
      // 第3天：主动恢复
      {
        'summary': '主动恢复日，保持轻度活动',
        'items': ['餐后轻松步行 15 分钟×2', '肩颈放松操 10 分钟', '睡前呼吸冥想 5 分钟'],
        'type': 'recovery',
      },
      // 第4天：有氧 + 核心
      {
        'summary': '$intensity 有氧 ${durations[3] - 10} 分钟 + 核心训练',
        'items': [
          '热身 5 分钟',
          '$cardioType ${durations[3] - 10} 分钟',
          '平板支撑 3 组',
          '腹肌卷曲 3 组',
          '放松拉伸 8 分钟'
        ],
        'type': 'cardio',
      },
      // 第5天：下肢力量
      {
        'summary': '下肢力量 ${durations[4]} 分钟（$strengthNote）',
        'items': [
          '热身 5 分钟',
          '深蹲 / 椅子辅助 3×12',
          '弓箭步 3×10',
          '臀桥 3×15',
          '小腿提踵 3×20',
          '拉伸 8 分钟'
        ],
        'type': 'strength',
      },
      // 第6天：有氧（本周最长）
      {
        'summary': '$intensity 有氧 ${durations[5]} 分钟，挑战本周最长时长',
        'items': [
          '热身 8 分钟',
          '$cardioType ${durations[5] - 10} 分钟',
          '拉伸 + 泡沫轴放松 12 分钟'
        ],
        'type': 'cardio',
      },
      // 第7天：休息
      {
        'summary': '休息日：轻量活动，注重恢复',
        'items': ['轻松散步 ${durations[6]} 分钟', '瑜伽 / 全身拉伸 15 分钟', '保证睡眠 7-8 小时'],
        'type': 'rest',
      },
    ];
  }

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
    return {
      'summary': '今日 ${items.length} 项测量',
      'items': items,
    };
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
    return {
      'summary': _buildSummary(),
      'risks': risks,
      'targetKcal': targetKcal,
      'bmr': bmr,
      'goalNote': goalNote,
      'dietNote': dietNote,
    };
  }

  String _buildSummary() {
    if (risks.isEmpty) return _buildHealthySummary();

    // 有风险：按严重程度描述主要问题
    final severe = risks
        .where((r) =>
            r.contains('危象') || r.contains('糖尿病标准') || r.contains('危险偏低'))
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

class TimeOfDayValue {
  const TimeOfDayValue({required this.hour, required this.minute});

  final int hour;
  final int minute;
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
