import 'package:flutter/foundation.dart';

import '../network/online_data_api.dart';
import '../notification/reminder_scheduler.dart';
import '../notification/web_push_service.dart';
import '../storage/app_database.dart';
import 'health_repository.dart';

class OnlineDataService {
  OnlineDataService({
    required AppDatabase database,
    required OnlineDataApi api,
    required HealthRepository repository,
    required ReminderScheduler reminderScheduler,
    required WebPushService webPushService,
  })  : _database = database,
        _api = api,
        _repository = repository,
        _reminderScheduler = reminderScheduler,
        _webPushService = webPushService;

  final AppDatabase _database;
  final OnlineDataApi _api;
  final HealthRepository _repository;
  final ReminderScheduler _reminderScheduler;
  final WebPushService _webPushService;

  Future<void> activateAccount(String userId) async {
    await _database.switchSpace(userId);
    _repository.signalChanged();
  }

  Future<void> syncAccount() async {
    await _database.bindOnline(_api);
    _repository.signalChanged();
    try {
      await _reminderScheduler.initialize();
      await _reminderScheduler.syncAll();
    } catch (error, stackTrace) {
      debugPrint('Reminder sync after online data failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> bindToAccount(String userId) async {
    await activateAccount(userId);
    await syncAccount();
  }

  Future<void> signOut({bool removePushSubscription = true}) async {
    try {
      await _webPushService.disable(notifyServer: removePushSubscription);
    } catch (_) {}
    await _database.unbindOnline();
    await _database.switchSpace('signed-out');
    _repository.signalChanged();
  }

  Future<void> reload() async {
    await _database.bindOnline(_api);
    _repository.signalChanged();
  }
}
