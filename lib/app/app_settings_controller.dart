import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsController extends ChangeNotifier {
  static const _seniorModeKey = 'senior_mode_v1';

  bool _seniorMode = false;

  bool get seniorMode => _seniorMode;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _seniorMode = preferences.getBool(_seniorModeKey) == true;
  }

  Future<void> setSeniorMode(bool value) async {
    if (_seniorMode == value) return;
    _seniorMode = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_seniorModeKey, value);
  }
}

final appSettingsController = AppSettingsController();
