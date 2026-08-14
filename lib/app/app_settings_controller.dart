import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsController extends ChangeNotifier {
  static const _seniorModeKey = 'senior_mode_v1';
  static const _waterGoalKey = 'water_goal_ml_v1';
  static const _seniorClockVoiceKey = 'senior_clock_voice_v1';

  bool _seniorMode = false;
  int? _waterGoalMl;
  bool _seniorClockVoice = false;

  bool get seniorMode => _seniorMode;
  int? get waterGoalMl => _waterGoalMl;
  bool get seniorClockVoice => _seniorClockVoice;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _seniorMode = preferences.getBool(_seniorModeKey) == true;
    _waterGoalMl = preferences.getInt(_waterGoalKey);
    _seniorClockVoice = preferences.getBool(_seniorClockVoiceKey) == true;
  }

  Future<void> setSeniorMode(bool value) async {
    if (_seniorMode == value) return;
    _seniorMode = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_seniorModeKey, value);
  }

  Future<void> setWaterGoalMl(int? value) async {
    if (_waterGoalMl == value) return;
    _waterGoalMl = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    if (value == null) {
      await preferences.remove(_waterGoalKey);
    } else {
      await preferences.setInt(_waterGoalKey, value);
    }
  }

  Future<void> setSeniorClockVoice(bool value) async {
    if (_seniorClockVoice == value) return;
    _seniorClockVoice = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_seniorClockVoiceKey, value);
  }
}

final appSettingsController = AppSettingsController();
