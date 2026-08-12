import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/storage/data_sync_merge.dart';

void main() {
  const base = {
    'health_indicator': [
      {'client_id': 'weight-1', 'value': 70, 'note': '晨起'}
    ],
  };

  test('不同记录的跨端修改自动合并', () {
    final result = mergeDataSyncTables(
      base: base,
      local: {
        'health_indicator': [
          ...base['health_indicator']!,
          {'client_id': 'bp-1', 'value': 120}
        ],
      },
      remote: {
        'health_indicator': [
          ...base['health_indicator']!,
          {'client_id': 'glucose-1', 'value': 5.6}
        ],
      },
    );

    expect(result.conflicts, isEmpty);
    expect(result.tables['health_indicator'], hasLength(3));
  });

  test('同一记录不同字段的修改自动合并', () {
    final result = mergeDataSyncTables(
      base: base,
      local: const {
        'health_indicator': [
          {'client_id': 'weight-1', 'value': 69, 'note': '晨起'}
        ],
      },
      remote: const {
        'health_indicator': [
          {'client_id': 'weight-1', 'value': 70, 'note': '空腹'}
        ],
      },
    );

    expect(result.conflicts, isEmpty);
    expect(result.tables['health_indicator']!.single['value'], 69);
    expect(result.tables['health_indicator']!.single['note'], '空腹');
  });

  test('同一字段双方修改时要求用户选择版本', () {
    final result = mergeDataSyncTables(
      base: base,
      local: const {
        'health_indicator': [
          {'client_id': 'weight-1', 'value': 69, 'note': '晨起'}
        ],
      },
      remote: const {
        'health_indicator': [
          {'client_id': 'weight-1', 'value': 71, 'note': '晨起'}
        ],
      },
    );

    expect(result.conflicts, hasLength(1));
    final key = result.conflicts.single.rowKey;
    final resolved = result.resolve({key: DataSyncConflictChoice.local});
    expect(resolved['health_indicator']!.single['value'], 69);
  });

  test('一端删除另一端未修改时保留删除结果', () {
    final result = mergeDataSyncTables(
      base: base,
      local: const {'health_indicator': []},
      remote: base,
    );

    expect(result.conflicts, isEmpty);
    expect(result.tables['health_indicator'], isEmpty);
  });

  test('一端删除另一端修改时要求用户确认', () {
    final result = mergeDataSyncTables(
      base: base,
      local: const {'health_indicator': []},
      remote: const {
        'health_indicator': [
          {'client_id': 'weight-1', 'value': 68, 'note': '晨起'}
        ],
      },
    );

    expect(result.conflicts, hasLength(1));
  });
}
