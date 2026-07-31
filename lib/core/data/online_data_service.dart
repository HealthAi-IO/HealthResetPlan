import '../network/online_data_api.dart';
import '../storage/app_database.dart';
import 'health_repository.dart';

class OnlineDataService {
  OnlineDataService({
    required AppDatabase database,
    required OnlineDataApi api,
    required HealthRepository repository,
  }) : _database = database,
       _api = api,
       _repository = repository;

  final AppDatabase _database;
  final OnlineDataApi _api;
  final HealthRepository _repository;

  Future<void> activateAccount(String userId) async {
    await _database.switchSpace(userId);
    _repository.signalChanged();
  }

  Future<void> syncAccount() async {
    await _database.bindOnline(_api);
    _repository.signalChanged();
  }

  Future<void> bindToAccount(String userId) async {
    await activateAccount(userId);
    await syncAccount();
  }

  Future<void> signOut() async {
    await _database.unbindOnline();
    await _database.switchSpace('signed-out');
    _repository.signalChanged();
  }

  Future<void> reload() async {
    await _database.bindOnline(_api);
    _repository.signalChanged();
  }
}
