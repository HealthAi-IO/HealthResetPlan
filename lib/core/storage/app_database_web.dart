import '../network/online_data_api.dart';

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

  String get activeSpace => 'local';

  Future<void> switchSpace(String space) async {}

  Future<bool> hasDataInSpace(String space) async => false;

  Future<void> moveSpace(String from, String to) async {}

  Future<void> bindOnline(OnlineDataApi api) async {
    throw UnsupportedError('当前数据库不支持在线数据');
  }

  Future<void> unbindOnline() async {}
}

class _WebAppDatabase extends AppDatabase {
  _WebAppDatabase() : super._();

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

  OnlineDataApi? _onlineApi;
  int _onlineVersion = 0;
  final Map<String, List<Map<String, Object?>>> _data = {
    for (final table in _tables) table: <Map<String, Object?>>[],
  };
  bool _opened = false;
  bool _inTransaction = false;
  String _activeSpace = 'local';

  @override
  String get activeSpace => _activeSpace;

  @override
  Future<void> switchSpace(String space) async {
    _activeSpace = space;
  }

  @override
  Future<bool> hasDataInSpace(String space) async {
    await open();
    return _data.values.any(
      (rows) => rows.any((row) => (row['space_id'] ?? 'local') == space),
    );
  }

  @override
  Future<void> moveSpace(String from, String to) async {
    if (from == to) return;
    await open();
    var changed = false;
    for (final rows in _data.values) {
      for (final row in rows) {
        if ((row['space_id'] ?? 'local') == from) {
          row['space_id'] = to;
          changed = true;
        }
      }
    }
    if (changed) await _persistIfNeeded();
  }

  @override
  Future<AppDatabase> open() async {
    if (_opened) return this;
    _opened = true;
    return this;
  }

  @override
  Future<void> close() async {
    if (!_opened) return;
    _opened = false;
  }

  List<Map<String, Object?>> _table(String name) =>
      _data.putIfAbsent(name, () => <Map<String, Object?>>[]);

  Future<void> _persist() async {
    final api = _onlineApi;
    if (api == null) return;
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _onlineTables) {
      tables[table] = _table(table)
          .where((row) => (row['space_id'] ?? 'online') == _activeSpace)
          .map((row) => Map<String, Object?>.from(row)..remove('space_id'))
          .toList();
    }
    try {
      final saved = await api.save(_onlineVersion, tables);
      _onlineVersion = saved.version;
    } catch (_) {
      await _loadOnline();
      rethrow;
    }
  }

  Future<void> _persistIfNeeded() async {
    if (_inTransaction) return;
    await _persist();
  }

  @override
  Future<void> bindOnline(OnlineDataApi api) async {
    _onlineApi = api;
    await _loadOnline();
  }

  @override
  Future<void> unbindOnline() async {
    _onlineApi = null;
    _onlineVersion = 0;
    for (final table in _onlineTables) {
      _data[table] = [];
    }
  }

  Future<void> _loadOnline() async {
    final api = _onlineApi;
    if (api == null) return;
    final space = _activeSpace;
    final snapshot = await api.load();
    if (!identical(_onlineApi, api) || _activeSpace != space) return;
    for (final table in _onlineTables) {
      _data[table] = (snapshot.tables[table] ?? const [])
          .map((row) => {...row, 'space_id': space})
          .toList();
    }
    _onlineVersion = snapshot.version;
  }

  static const _onlineTables = [
    'user_profile',
    'health_indicator',
    'plan',
    'clock_record',
    'reminder',
    'health_report',
    'meal_record',
    'ai_session',
    'ai_message',
  ];

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
    rows = rows.where((row) => row['space_id'] == _activeSpace).toList();
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
    final row = Map<String, Object?>.from(values)..['space_id'] = _activeSpace;
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
      if (row['space_id'] == _activeSpace &&
          (where == null || _matchesWhere(row, where, whereArgs))) {
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
      rows.removeWhere((row) => row['space_id'] == _activeSpace);
    } else {
      rows.removeWhere(
        (row) =>
            row['space_id'] == _activeSpace &&
            _matchesWhere(row, where, whereArgs),
      );
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
