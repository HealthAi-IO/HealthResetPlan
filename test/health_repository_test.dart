import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';
import 'package:health_reset_plan/core/data/health_repository.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';

void main() {
  test('incomplete profile does not expose estimated nutrition targets', () {
    final targets = DailyNutritionTargets.fromProfile(UserProfileData.empty());

    expect(targets.calories, 0);
    expect(targets.proteinG, 0);
    expect(targets.carbsG, 0);
    expect(targets.fatG, 0);
  });

  test('profile is complete only for valid adults and physical values', () {
    final currentYear = DateTime.now().year;
    final valid = UserProfileData.empty().copyWith(
      gender: 'female',
      birthYear: currentYear - 18,
      heightCm: 165,
      weightKg: 60,
    );

    expect(valid.isComplete, isTrue);
    expect(valid.copyWith(birthYear: currentYear - 17).isComplete, isFalse);
    expect(valid.copyWith(birthYear: currentYear - 101).isComplete, isFalse);
    expect(valid.copyWith(gender: 'unknown').isComplete, isFalse);
    expect(valid.copyWith(heightCm: 99).isComplete, isFalse);
    expect(valid.copyWith(weightKg: 301).isComplete, isFalse);
  });

  test('critical indicator boundaries are classified consistently', () {
    expect(
      HealthSafety.isCriticalIndicator(
        'bp',
        {'systolic': 179, 'diastolic': 119},
      ),
      isFalse,
    );
    expect(
      HealthSafety.isCriticalIndicator(
        'bp',
        {'systolic': 180, 'diastolic': 80},
      ),
      isTrue,
    );
    expect(
      HealthSafety.isCriticalIndicator('spo2', {'spo2Pct': 90}),
      isFalse,
    );
    expect(
      HealthSafety.isCriticalIndicator('spo2', {'spo2Pct': 89}),
      isTrue,
    );
  });

  test('initialize starts with empty local dashboard data', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());

    await repo.initialize();
    final dashboard = await repo.loadDashboard();

    expect(dashboard.profile, isNull);
    expect(dashboard.indicators, isEmpty);
    expect(dashboard.plans, isEmpty);
    expect(dashboard.reminders, isEmpty);
    expect(dashboard.clockRecords, isEmpty);
    expect(dashboard.weightTrend(), isEmpty);
  });

  test('weight indicator updates profile weight', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());
    await repo.initialize();
    await repo.saveProfile(
      UserProfileData.empty().copyWith(
        nickname: '测试用户',
        gender: 'female',
        birthYear: 1990,
        heightCm: 165,
        weightKg: 70,
      ),
    );

    await repo.addIndicator(
      type: 'weight',
      payload: {'weightKg': 72.3},
    );

    final profile = await repo.loadProfile();
    final latestWeight = (await repo.loadIndicators(type: 'weight')).first;
    expect(profile?.weightKg, 72.3);
    expect(latestWeight.displayValue, '72.3 kg');
  });

  test('weekly plan adapts to obesity and high blood pressure data', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());
    await repo.initialize();
    await repo.saveProfile(
      UserProfileData.empty().copyWith(
        nickname: '测试用户',
        gender: 'male',
        birthYear: 1988,
        heightCm: 168,
        weightKg: 90,
      ),
    );

    await repo.addIndicator(
      type: 'bp',
      payload: {'systolic': 150, 'diastolic': 95},
    );
    await repo.generateWeeklyPlan();

    final meals = await repo.loadPlans();
    final firstMeal = meals.firstWhere((item) => item.type == 'meal');
    expect(firstMeal.summary, contains('低盐'));
    expect(meals.where((item) => item.type == 'exercise'), hasLength(7));
  });

  test('weekly plan does not require a nickname', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());
    await repo.initialize();
    await repo.saveProfile(
      UserProfileData.empty().copyWith(
        gender: 'female',
        birthYear: 1990,
        heightCm: 165,
        weightKg: 52,
      ),
    );

    await repo.generateWeeklyPlan();

    expect(await repo.loadPlans(), isNotEmpty);
  });

  test('blood pressure crisis blocks every weekly plan', () async {
    for (final bp in [(180, 80), (120, 120), (181, 121)]) {
      final repo = HealthRepository(database: _MemoryAppDatabase());
      await repo.initialize();
      await repo.saveProfile(_validProfile());
      await repo.addIndicator(
        type: 'bp',
        payload: {'systolic': bp.$1, 'diastolic': bp.$2},
      );

      await expectLater(
        repo.generateWeeklyPlan(),
        throwsA(isA<PlanBlockedException>()),
      );
      final plans = await repo.loadPlans();
      expect(plans.where((plan) => plan.type == 'exercise'), isEmpty);
      final risk = plans.firstWhere((plan) => plan.type == 'risk');
      expect(risk.payload['isCritical'], isTrue);
      expect(risk.payload['targetKcal'], 0);
      expect(risk.summary, contains('立即就医'));
    }
  });

  test('blood pressure below crisis boundary still allows a plan', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());
    await repo.initialize();
    await repo.saveProfile(_validProfile());
    await repo.addIndicator(
      type: 'bp',
      payload: {'systolic': 179, 'diastolic': 119},
    );

    await repo.generateWeeklyPlan();

    expect(await repo.loadPlans(), isNotEmpty);
  });

  test('new normal blood pressure clears the critical plan state', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());
    await repo.initialize();
    await repo.saveProfile(_validProfile());
    await repo.addIndicator(
      type: 'bp',
      payload: {'systolic': 180, 'diastolic': 80},
      measuredAt: DateTime(2026, 7, 21),
    );
    await repo.addIndicator(
      type: 'bp',
      payload: {'systolic': 120, 'diastolic': 80},
      measuredAt: DateTime(2026, 7, 22),
    );

    await repo.generateWeeklyPlan();

    final plans = await repo.loadPlans();
    expect(plans.where((plan) => plan.type == 'exercise'), hasLength(7));
    final risk = plans.firstWhere((plan) => plan.type == 'risk');
    expect(risk.payload['isCritical'], isFalse);
  });

  test('oxygen saturation below 90 blocks every weekly plan', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());
    await repo.initialize();
    await repo.saveProfile(_validProfile());
    await repo.addIndicator(type: 'spo2', payload: {'spo2Pct': 89});

    await expectLater(
      repo.generateWeeklyPlan(),
      throwsA(isA<PlanBlockedException>()),
    );
    expect(
      (await repo.loadPlans()).where((plan) => plan.type == 'exercise'),
      isEmpty,
    );
  });

  test('report record is saved as dirty sync data', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());
    await repo.initialize();

    final recordedAt = DateTime(2026, 6, 9, 8);
    await repo.saveReportRecord(
      clientId: 'report-1',
      imagePath: '',
      reportTime: recordedAt,
      summary: 'Blood pressure noted',
      rawText: 'BP 120/80',
      structured: {
        'indicators': [
          {'name': 'BP', 'value': '120/80'},
        ],
      },
      provider: 'qwen-vl',
    );

    final reports = await repo.loadReportRecords();
    final report = reports.single;

    expect(report.clientId, 'report-1');
    expect(report.reportTime, recordedAt.millisecondsSinceEpoch);
    expect(report.version, 1);
    expect(report.isDirty, 1);
    expect(report.syncAt, 0);
    expect(report.indicatorCount, 1);
  });
}

UserProfileData _validProfile() => UserProfileData.empty().copyWith(
      nickname: '测试用户',
      gender: 'female',
      birthYear: 1990,
      heightCm: 165,
      weightKg: 60,
    );

class _MemoryAppDatabase implements AppDatabase {
  static const _tables = [
    'user_profile',
    'health_indicator',
    'plan',
    'clock_record',
    'reminder',
    'sync_queue',
    'health_report',
  ];

  final Map<String, List<Map<String, Object?>>> _data = {
    for (final table in _tables) table: <Map<String, Object?>>[],
  };

  @override
  Future<AppDatabase> open() async => this;

  @override
  Future<void> close() async {}

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    var rows =
        _table(table).map((row) => Map<String, Object?>.from(row)).toList();
    if (where != null && where.trim().isNotEmpty) {
      rows = rows.where((row) => _matchesWhere(row, where, whereArgs)).toList();
    }
    if (orderBy != null && orderBy.trim().isNotEmpty) {
      rows = _sortRows(rows, orderBy);
    }
    if (limit != null && rows.length > limit) {
      rows = rows.sublist(0, limit);
    }
    return rows;
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    bool replace = false,
  }) async {
    final rows = _table(table);
    final row = Map<String, Object?>.from(values);
    final id = _intValue(row['id']) ?? _nextId(rows);
    row['id'] = id;
    if (replace) {
      final index = rows.indexWhere((entry) => _intValue(entry['id']) == id);
      if (index >= 0) {
        rows[index] = row;
        return id;
      }
    }
    rows.add(row);
    return id;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    var updated = 0;
    final rows = _table(table);
    for (var i = 0; i < rows.length; i++) {
      if (where == null || _matchesWhere(rows[i], where, whereArgs)) {
        rows[i].addAll(values);
        updated++;
      }
    }
    return updated;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final rows = _table(table);
    final original = rows.length;
    if (where == null || where.trim().isEmpty) {
      rows.clear();
    } else {
      rows.removeWhere((row) => _matchesWhere(row, where, whereArgs));
    }
    return original - rows.length;
  }

  @override
  Future<int> count(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    return (await query(table, where: where, whereArgs: whereArgs)).length;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(AppDatabase txn) action) async {
    final snapshot = _deepCopy(_data);
    try {
      return await action(this);
    } catch (_) {
      _data
        ..clear()
        ..addAll(_deepCopy(snapshot));
      rethrow;
    }
  }

  List<Map<String, Object?>> _table(String name) {
    return _data.putIfAbsent(name, () => <Map<String, Object?>>[]);
  }

  bool _matchesWhere(
    Map<String, Object?> row,
    String where,
    List<Object?>? args,
  ) {
    final clauses = where.split(RegExp(r'\s+AND\s+', caseSensitive: false));
    var argIndex = 0;
    for (final clause in clauses) {
      final match = RegExp(r'^\s*([a-zA-Z0-9_]+)\s*(>=|<=|!=|>|<|=)\s*\?\s*$')
          .firstMatch(clause);
      if (match == null || args == null || argIndex >= args.length) {
        return false;
      }
      final column = match.group(1)!;
      final op = match.group(2)!;
      final argVal = args[argIndex++];
      if (!_applyOp(row[column], op, argVal)) return false;
    }
    return true;
  }

  bool _applyOp(Object? rowVal, String op, Object? argVal) {
    if (op == '=') return _valueEquals(rowVal, argVal);
    if (op == '!=') return !_valueEquals(rowVal, argVal);
    final cmp = _compareValues(rowVal, argVal);
    return switch (op) {
      '>=' => cmp >= 0,
      '<=' => cmp <= 0,
      '>' => cmp > 0,
      '<' => cmp < 0,
      _ => false,
    };
  }

  List<Map<String, Object?>> _sortRows(
    List<Map<String, Object?>> rows,
    String orderBy,
  ) {
    final clauses = orderBy
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    rows.sort((a, b) {
      for (final clause in clauses) {
        final parts = clause.split(RegExp(r'\s+'));
        final column = parts.first;
        final descending = parts.length > 1 && parts[1].toLowerCase() == 'desc';
        final cmp = _compareValues(a[column], b[column]);
        if (cmp != 0) return descending ? -cmp : cmp;
      }
      return 0;
    });
    return rows;
  }

  int _compareValues(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  bool _valueEquals(Object? a, Object? b) {
    if (a == b) return true;
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    return '$a' == '$b';
  }

  int _nextId(List<Map<String, Object?>> rows) {
    var maxId = 0;
    for (final row in rows) {
      final id = _intValue(row['id']) ?? 0;
      if (id > maxId) maxId = id;
    }
    return maxId + 1;
  }

  int? _intValue(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  Map<String, List<Map<String, Object?>>> _deepCopy(
    Map<String, List<Map<String, Object?>>> source,
  ) {
    return {
      for (final entry in source.entries)
        entry.key:
            entry.value.map((row) => Map<String, Object?>.from(row)).toList(),
    };
  }
}
