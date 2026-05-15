import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_repository.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';

void main() {
  test('initialize seeds local dashboard data', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());

    await repo.initialize();
    final dashboard = await repo.loadDashboard();

    expect(dashboard.profile?.nickname, '本地用户');
    expect(dashboard.plans, hasLength(14));
    expect(dashboard.reminders, hasLength(4));
    expect(dashboard.clockRecords, hasLength(3));
    expect(dashboard.weightTrend(), hasLength(7));
  });

  test('weight indicator updates profile weight', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());
    await repo.initialize();

    await repo.addIndicator(
      type: 'weight',
      payload: {'weightKg': 72.3},
      measuredAt: DateTime(2026, 5, 13, 7),
    );

    final profile = await repo.loadProfile();
    final latestWeight = (await repo.loadIndicators(type: 'weight')).first;
    expect(profile?.weightKg, 72.3);
    expect(latestWeight.displayValue, '72.3 kg');
  });

  test('weekly plan adapts to obesity and high blood pressure data', () async {
    final repo = HealthRepository(database: _MemoryAppDatabase());
    await repo.initialize();

    final existing = await repo.loadProfile();
    await repo.saveProfile(
      existing!.copyWith(heightCm: 168, weightKg: 90),
    );
    await repo.addIndicator(
      type: 'bp',
      payload: {'systolic': 150, 'diastolic': 95},
      measuredAt: DateTime(2026, 5, 13, 8),
    );
    await repo.generateWeeklyPlan();

    final meals = await repo.loadPlans();
    final firstMeal = meals.firstWhere((item) => item.type == 'meal');
    expect(firstMeal.summary, contains('1500 kcal'));
    expect(firstMeal.summary, contains('低盐'));
    expect(meals.where((item) => item.type == 'exercise'), hasLength(7));
  });
}

class _MemoryAppDatabase implements AppDatabase {
  static const _tables = [
    'user_profile',
    'health_indicator',
    'plan',
    'clock_record',
    'reminder',
    'sync_queue',
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
      final match =
          RegExp(r'^\s*([a-zA-Z0-9_]+)\s*=\s*\?\s*$').firstMatch(clause);
      if (match == null || args == null || argIndex >= args.length) {
        return false;
      }
      final column = match.group(1)!;
      if (!_valueEquals(row[column], args[argIndex++])) {
        return false;
      }
    }
    return true;
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
