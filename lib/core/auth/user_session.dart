import 'package:shared_preferences/shared_preferences.dart';

class UserSession {
  UserSession._();
  static final UserSession instance = UserSession._();

  static const _key = 'user_display_name';

  String _name = '';
  String get name => _name;
  bool get hasName => _name.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString(_key) ?? '';
  }

  Future<void> setName(String name) async {
    _name = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _name);
  }

  Future<void> clear() async {
    _name = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
