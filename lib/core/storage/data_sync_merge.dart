import 'package:flutter/foundation.dart';

enum DataSyncConflictChoice { local, remote }

class DataSyncRowConflict {
  const DataSyncRowConflict({
    required this.table,
    required this.rowKey,
    required this.base,
    required this.local,
    required this.remote,
  });

  final String table;
  final String rowKey;
  final Map<String, Object?>? base;
  final Map<String, Object?>? local;
  final Map<String, Object?>? remote;
}

class DataSyncMergeResult {
  const DataSyncMergeResult({
    required this.tables,
    required this.conflicts,
  });

  final Map<String, List<Map<String, Object?>>> tables;
  final List<DataSyncRowConflict> conflicts;

  Map<String, List<Map<String, Object?>>> resolve(
    Map<String, DataSyncConflictChoice> choices,
  ) {
    final resolved = _copyTables(tables);
    for (final conflict in conflicts) {
      final choice = choices[conflict.rowKey];
      if (choice == null) {
        throw StateError('仍有同步冲突尚未处理');
      }
      final rows = resolved.putIfAbsent(conflict.table, () => []);
      rows.removeWhere(
          (row) => _rowKey(conflict.table, row) == conflict.rowKey);
      final selected = choice == DataSyncConflictChoice.local
          ? conflict.local
          : conflict.remote;
      if (selected != null) rows.add(Map<String, Object?>.from(selected));
    }
    return resolved;
  }
}

DataSyncMergeResult mergeDataSyncTables({
  required Map<String, List<Map<String, Object?>>> base,
  required Map<String, List<Map<String, Object?>>> local,
  required Map<String, List<Map<String, Object?>>> remote,
}) {
  final tables = <String, List<Map<String, Object?>>>{};
  final conflicts = <DataSyncRowConflict>[];
  final tableNames = {...base.keys, ...local.keys, ...remote.keys};

  for (final table in tableNames) {
    final baseRows = _indexRows(table, base[table] ?? const []);
    final localRows = _indexRows(table, local[table] ?? const []);
    final remoteRows = _indexRows(table, remote[table] ?? const []);
    final mergedRows = <Map<String, Object?>>[];
    final rowKeys = {...baseRows.keys, ...localRows.keys, ...remoteRows.keys};

    for (final key in rowKeys) {
      final baseRow = baseRows[key];
      final localRow = localRows[key];
      final remoteRow = remoteRows[key];
      final merged = _mergeRow(baseRow, localRow, remoteRow);
      if (merged.conflict) {
        conflicts.add(DataSyncRowConflict(
          table: table,
          rowKey: key,
          base: baseRow,
          local: localRow,
          remote: remoteRow,
        ));
        if (remoteRow != null) {
          mergedRows.add(Map<String, Object?>.from(remoteRow));
        }
      } else if (merged.row != null) {
        mergedRows.add(merged.row!);
      }
    }
    tables[table] = mergedRows;
  }
  return DataSyncMergeResult(tables: tables, conflicts: conflicts);
}

class _RowMerge {
  const _RowMerge(this.row, {this.conflict = false});

  final Map<String, Object?>? row;
  final bool conflict;
}

_RowMerge _mergeRow(
  Map<String, Object?>? base,
  Map<String, Object?>? local,
  Map<String, Object?>? remote,
) {
  if (mapEquals(local, remote)) return _RowMerge(_copyRow(local));
  if (mapEquals(local, base)) return _RowMerge(_copyRow(remote));
  if (mapEquals(remote, base)) return _RowMerge(_copyRow(local));
  if (local == null || remote == null) {
    return const _RowMerge(null, conflict: true);
  }

  final merged = <String, Object?>{};
  final fields = {...?base?.keys, ...local.keys, ...remote.keys};
  for (final field in fields) {
    final baseValue = base?[field];
    final localValue = local[field];
    final remoteValue = remote[field];
    if (_valueEquals(localValue, remoteValue)) {
      merged[field] = localValue;
    } else if (_valueEquals(localValue, baseValue)) {
      merged[field] = remoteValue;
    } else if (_valueEquals(remoteValue, baseValue)) {
      merged[field] = localValue;
    } else {
      return const _RowMerge(null, conflict: true);
    }
  }
  return _RowMerge(merged);
}

Map<String, Map<String, Object?>> _indexRows(
  String table,
  List<Map<String, Object?>> rows,
) =>
    {
      for (final row in rows) _rowKey(table, row): row,
    };

String _rowKey(String table, Map<String, Object?> row) {
  final clientId = row['client_id']?.toString();
  final id = row['id']?.toString();
  final identity = clientId?.isNotEmpty == true ? clientId! : id;
  if (identity == null || identity.isEmpty) {
    throw FormatException('$table 存在缺少标识的数据');
  }
  return '$table:$identity';
}

bool _valueEquals(Object? left, Object? right) {
  if (left is Map && right is Map) return mapEquals(left, right);
  if (left is List && right is List) return listEquals(left, right);
  return left == right;
}

Map<String, Object?>? _copyRow(Map<String, Object?>? row) =>
    row == null ? null : Map<String, Object?>.from(row);

Map<String, List<Map<String, Object?>>> _copyTables(
  Map<String, List<Map<String, Object?>>> source,
) =>
    {
      for (final entry in source.entries)
        entry.key: entry.value.map(Map<String, Object?>.from).toList(),
    };
