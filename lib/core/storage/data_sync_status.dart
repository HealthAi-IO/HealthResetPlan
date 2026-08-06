import 'package:flutter/foundation.dart';

enum DataSyncPhase { idle, syncing, synced, failed }

class DataSyncStatusController extends ChangeNotifier {
  DataSyncPhase _phase = DataSyncPhase.idle;
  DateTime? _lastSyncedAt;
  String? _errorMessage;
  Future<void> Function()? _retry;

  DataSyncPhase get phase => _phase;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get errorMessage => _errorMessage;
  bool get canRetry => _retry != null;

  void attachRetry(Future<void> Function()? retry) => _retry = retry;

  void markSyncing() {
    _phase = DataSyncPhase.syncing;
    _errorMessage = null;
    notifyListeners();
  }

  void markSynced() {
    _phase = DataSyncPhase.synced;
    _lastSyncedAt = DateTime.now();
    _errorMessage = null;
    notifyListeners();
  }

  void markFailed(Object error) {
    _phase = DataSyncPhase.failed;
    _errorMessage = '同步失败，请检查网络后重试';
    notifyListeners();
  }

  Future<void> retry() async {
    final retry = _retry;
    if (retry == null) return;
    await retry();
  }
}

final dataSyncStatusController = DataSyncStatusController();
