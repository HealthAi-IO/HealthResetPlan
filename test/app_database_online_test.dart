import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:health_reset_plan/core/network/online_data_api.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';

void main() {
  test('business writes require an online account', () async {
    final database = AppDatabase.instance;
    await database.open();
    await database.switchSpace('signed-out');

    await expectLater(
      database.insert('user_profile', _profile('offline')),
      throwsA(isA<OnlineDataRequiredException>()),
    );
  });

  test('concurrent online changes are saved in order', () async {
    final database = AppDatabase.instance;
    final api = _TestOnlineDataApi(delayFirstSave: true);
    await database.switchSpace('queue-test');
    await database.bindOnline(api);

    final first = database.insert('user_profile', _profile('first'));
    await api.firstSaveStarted.future;
    final second = database.insert('user_profile', _profile('second'));
    api.allowFirstSave.complete();

    await Future.wait([first, second]);
    expect(api.savedRowCounts, [1, 2]);
    await database.unbindOnline();
  });

  test('failed server save rolls back the memory cache', () async {
    final database = AppDatabase.instance;
    final api = _TestOnlineDataApi(failSaveNumber: 1);
    await database.switchSpace('rollback-test');
    await database.bindOnline(api);

    await expectLater(
      database.insert('user_profile', _profile('unsaved')),
      throwsStateError,
    );
    expect(await database.query('user_profile'), isEmpty);
    await database.unbindOnline();
  });

  test('a later failed save does not roll back an earlier success', () async {
    final database = AppDatabase.instance;
    final api = _TestOnlineDataApi(
      delayFirstSave: true,
      failSaveNumber: 2,
    );
    await database.switchSpace('partial-rollback-test');
    await database.bindOnline(api);

    final first = database.insert('user_profile', _profile('first'));
    await api.firstSaveStarted.future;
    final second = database.insert('user_profile', _profile('second'));
    api.allowFirstSave.complete();

    await first;
    await expectLater(second, throwsStateError);
    final rows = await database.query('user_profile');
    expect(rows.map((row) => row['nickname']), ['first']);
    await database.unbindOnline();
  });

  test('a new change still saves after an earlier queued save failed',
      () async {
    final database = AppDatabase.instance;
    final api = _TestOnlineDataApi(failSaveNumber: 1);
    await database.switchSpace('recovery-after-failure-test');
    await database.bindOnline(api);

    await expectLater(
      database.insert('user_profile', _profile('failed')),
      throwsStateError,
    );
    await database.insert('user_profile', _profile('recovered'));

    expect(api.savedRowCounts, [1, 1]);
    expect(
      (await database.query('user_profile')).single['nickname'],
      'recovered',
    );
    await database.unbindOnline();
  });

  test('a queued change excludes an earlier concurrent change that failed',
      () async {
    final database = AppDatabase.instance;
    final api = _TestOnlineDataApi(delayFirstSave: true, failSaveNumber: 1);
    await database.switchSpace('concurrent-recovery-test');
    await database.bindOnline(api);

    final failed = database.insert('user_profile', _profile('failed'));
    await api.firstSaveStarted.future;
    final recovered = database.insert('user_profile', _profile('recovered'));
    api.allowFirstSave.complete();

    await expectLater(failed, throwsStateError);
    await recovered;
    expect(api.savedNicknames, [
      ['failed'],
      ['recovered'],
    ]);
    expect(
      (await database.query('user_profile')).single['nickname'],
      'recovered',
    );
    await database.unbindOnline();
  });
}

Map<String, Object?> _profile(String nickname) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return {
    'user_id': 'test-user',
    'nickname': nickname,
    'created_at': now,
    'updated_at': now,
  };
}

class _TestOnlineDataApi extends OnlineDataApi {
  _TestOnlineDataApi({this.delayFirstSave = false, this.failSaveNumber})
      : super(client: ApiClient(baseUrl: 'http://localhost'));

  final bool delayFirstSave;
  final int? failSaveNumber;
  final firstSaveStarted = Completer<void>();
  final allowFirstSave = Completer<void>();
  final List<int> savedRowCounts = [];
  final List<List<Object?>> savedNicknames = [];

  @override
  Future<OnlineDataSnapshot> load() async =>
      const OnlineDataSnapshot(version: 0, tables: {});

  @override
  Future<OnlineDataSnapshot> save(
    int version,
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    savedRowCounts.add(tables['user_profile']?.length ?? 0);
    savedNicknames.add(
      (tables['user_profile'] ?? const [])
          .map((row) => row['nickname'])
          .toList(),
    );
    if (savedRowCounts.length == 1) {
      if (!firstSaveStarted.isCompleted) firstSaveStarted.complete();
      if (delayFirstSave) await allowFirstSave.future;
    }
    if (savedRowCounts.length == failSaveNumber) {
      throw StateError('save failed');
    }
    return OnlineDataSnapshot(version: version + 1, tables: tables);
  }
}
