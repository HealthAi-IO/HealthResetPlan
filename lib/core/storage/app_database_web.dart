import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = _WebAppDatabase();

  Future<AppDatabase> open();
  Future<void> close();

  Future<List<Map<String, Object?>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  });

  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    bool replace = false,
  });

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<int> count(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<T> transaction<T>(Future<T> Function(AppDatabase txn) action);
}

class _WebAppDatabase extends AppDatabase {
  _WebAppDatabase() : super._();

  static const String _storageKey = 'health_reset_plan_web_db_v1';
  static const _tables = [
    'user_profile',
    'health_indicator',
    'plan',
    'clock_record',
    'reminder',
    'sync_queue',
    'health_report',
    'meal_record',
    'ai_session',
    'ai_message',
  ];

  SharedPreferences? _prefs;
  final Map<String, List<Map<String, Object?>>> _data = {
    for (final table in _tables) table: <Map<String, Object?>>[],
  };
  bool _opened = false;
  bool _inTransaction = false;

  @override
  Future<AppDatabase> open() async {
    if (_opened) return this;
    _prefs ??= await SharedPreferences.getInstance();
    final encoded = _prefs!.getString(_storageKey);
    if (encoded != null && encoded.isNotEmpty) {
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        for (final table in _tables) {
          final rows = decoded[table];
          if (rows is List) {
            _data[table] = rows
                .whereType<Map>()
                .map((row) => row.map((key, value) => MapEntry('$key', value)))
                .toList();
          }
        }
      }
    }
    _opened = true;
    return this;
  }

  @override
  Future<void> close() async {
    if (!_opened) return;
    await _persist();
    _opened = false;
  }

  List<Map<String, Object?>> _table(String name) =>
      _data.putIfAbsent(name, () => <Map<String, Object?>>[]);

  Future<void> _persist() async {
    if (_prefs == null) return;
    await _prefs!.setString(_storageKey, jsonEncode(_data));
  }

  Future<void> _persistIfNeeded() async {
    if (_inTransaction) return;
    await _persist();
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    await open();
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
    await open();
    final rows = _table(table);
    final row = Map<String, Object?>.from(values);
    final id = _intValue(row['id']);
    if (replace && id != null) {
      final index = rows.indexWhere((entry) => _intValue(entry['id']) == id);
      if (index >= 0) {
        rows[index] = row;
        await _persistIfNeeded();
        return id;
      }
    }
    final nextId = id ?? _nextId(rows);
    row['id'] = nextId;
    rows.add(row);
    await _persistIfNeeded();
    return nextId;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    await open();
    final rows = _table(table);
    var updated = 0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (where == null || _matchesWhere(row, where, whereArgs)) {
        row.addAll(values);
        rows[i] = row;
        updated++;
      }
    }
    if (updated > 0) {
      await _persistIfNeeded();
    }
    return updated;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    await open();
    final rows = _table(table);
    final original = rows.length;
    if (where == null || where.trim().isEmpty) {
      rows.clear();
    } else {
      rows.removeWhere((row) => _matchesWhere(row, where, whereArgs));
    }
    final deleted = original - rows.length;
    if (deleted > 0) {
      await _persistIfNeeded();
    }
    return deleted;
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
    await open();
    final snapshot = _deepCopy(_data);
    final previous = _inTransaction;
    _inTransaction = true;
    try {
      final result = await action(this);
      _inTransaction = previous;
      await _persist();
      return result;
    } catch (e) {
      _data
        ..clear()
        ..addAll(_deepCopy(snapshot));
      _inTransaction = previous;
      await _persist();
      rethrow;
    }
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
      final expected = args[argIndex++];
      if (!_applyOp(row[column], op, expected)) {
        return false;
      }
    }
    return true;
  }

  bool _applyOp(Object? rowValue, String op, Object? expected) {
    if (op == '=') return _valueEquals(rowValue, expected);
    if (op == '!=') return !_valueEquals(rowValue, expected);
    final comparison = _compareValues(rowValue, expected);
    switch (op) {
      case '>=':
        return comparison >= 0;
      case '<=':
        return comparison <= 0;
      case '>':
        return comparison > 0;
      case '<':
        return comparison < 0;
      default:
        return false;
    }
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
        if (cmp != 0) {
          return descending ? -cmp : cmp;
        }
      }
      return 0;
    });
    return rows;
  }

  int _compareValues(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) {
      return a.compareTo(b);
    }
    return a.toString().compareTo(b.toString());
  }

  bool _valueEquals(Object? a, Object? b) {
    if (a == b) return true;
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    if (a is num) {
      final parsed = num.tryParse('$b');
      return parsed != null && a.toDouble() == parsed.toDouble();
    }
    if (b is num) {
      final parsed = num.tryParse('$a');
      return parsed != null && parsed.toDouble() == b.toDouble();
    }
    return '$a' == '$b';
  }

  int _nextId(List<Map<String, Object?>> rows) {
    var maxId = 0;
    for (final row in rows) {
      final id = _intValue(row['id']) ?? 0;
      if (id > maxId) {
        maxId = id;
      }
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

