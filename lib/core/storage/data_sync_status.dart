import 'package:flutter/foundation.dart';

import 'data_sync_merge.dart';

enum DataSyncPhase { idle, syncing, synced, conflict, failed }

class DataSyncStatusController extends ChangeNotifier {
  DataSyncPhase _phase = DataSyncPhase.idle;
  DateTime? _lastSyncedAt;
  String? _errorMessage;
  Future<void> Function()? _retry;
  DataSyncMergeResult? _conflict;
  Future<void> Function(Map<String, DataSyncConflictChoice>)? _resolve;

  DataSyncPhase get phase => _phase;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get errorMessage => _errorMessage;
  bool get canRetry => _retry != null;
  DataSyncMergeResult? get conflict => _conflict;
  bool get hasConflict => _phase == DataSyncPhase.conflict;

  void attachRetry(Future<void> Function()? retry) => _retry = retry;

  void markSyncing() {
    _phase = DataSyncPhase.syncing;
    _errorMessage = null;
    _conflict = null;
    notifyListeners();
  }

  void markSynced() {
    _phase = DataSyncPhase.synced;
    _lastSyncedAt = DateTime.now();
    _errorMessage = null;
    _conflict = null;
    _resolve = null;
    notifyListeners();
  }

  void markFailed(Object error) {
    _phase = DataSyncPhase.failed;
    _errorMessage = '同步失败，请检查网络后重试';
    notifyListeners();
  }

  void markConflict(
    DataSyncMergeResult conflict,
    Future<void> Function(Map<String, DataSyncConflictChoice>) resolve,
  ) {
    _phase = DataSyncPhase.conflict;
    _errorMessage = '发现其他设备的修改，请确认保留内容';
    _conflict = conflict;
    _resolve = resolve;
    notifyListeners();
  }

  Future<void> resolveConflict(
    Map<String, DataSyncConflictChoice> choices,
  ) async {
    final resolve = _resolve;
    if (resolve == null) return;
    markSyncing();
    try {
      await resolve(choices);
      markSynced();
    } catch (error) {
      markFailed(error);
      rethrow;
    }
  }

  Future<void> retry() async {
    final retry = _retry;
    if (retry == null) return;
    await retry();
  }
}

final dataSyncStatusController = DataSyncStatusController();
