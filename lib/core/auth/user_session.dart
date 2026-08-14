import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户会话。
///
/// 仅保存登录会话与非业务偏好，健康业务数据不在本机持久化。
class UserSession extends ChangeNotifier {
  UserSession._();
  static final UserSession instance = UserSession._();

  // 公开存储（昵称）
  static const _kName = 'user_display_name';
  static const _kAvatarUrl = 'user_avatar_url';
  static const _kUserId = 'user_account_id';
  static const _kLegacyAccountIdentifier = 'user_account_identifier';
  static const _kAccountLoginRequired = 'account_login_required';
  static const _kSessionExpired = 'session_expired';
  static const welcomeLetterPendingUserKey =
      'welcome_letter_pending_user_id_v1';

  // 安全存储（Token）
  static const _kAccess = 'hrp_access_token';
  static const _kRefresh = 'hrp_refresh_token';
  static const _kPasswordPromptRequired = 'hrp_password_prompt_required';

  // 用 flutter_secure_storage 保存 Token；昵称用 SharedPreferences
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );

  String _name = '';
  String _avatarUrl = '';
  String? _userId;
  String? _accessToken;
  String? _refreshToken;
  bool _passwordPromptRequired = false;
  bool _accountLoginRequired = false;
  bool _sessionExpired = false;

  String get name => _name;
  String get avatarUrl => _avatarUrl;
  String? get userId => _userId;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get passwordPromptRequired => _passwordPromptRequired;
  bool get accountLoginRequired => _accountLoginRequired;
  bool get sessionExpired => _sessionExpired;

  bool get hasName => _name.isNotEmpty;

  /// 是否已绑定真实账号（拥有 JWT Token）
  bool get isAccountLogin =>
      _userId != null && _accessToken != null && _accessToken!.isNotEmpty;

  /// 启动时调用：从持久化中加载昵称和 Token
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString(_kName) ?? '';
    _avatarUrl = prefs.getString(_kAvatarUrl) ?? '';
    _userId = prefs.getString(_kUserId);
    await prefs.remove(_kLegacyAccountIdentifier);

    _accessToken = await _secureStorage.read(key: _kAccess);
    _refreshToken = await _secureStorage.read(key: _kRefresh);
    _passwordPromptRequired = prefs.getBool(_kPasswordPromptRequired) ?? false;
    _accountLoginRequired = prefs.getBool(_kAccountLoginRequired) ?? false;
    _sessionExpired = prefs.getBool(_kSessionExpired) ?? false;
  }

  /// 更新当前账号的显示昵称缓存。
  Future<void> setName(String name) async {
    _name = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, _name);
    notifyListeners();
  }

  Future<void> setAccountDisplay({String? nickname, String? avatarUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    if (nickname != null && nickname.trim().isNotEmpty) {
      _name = nickname.trim();
      await prefs.setString(_kName, _name);
    }
    if (avatarUrl != null) {
      _avatarUrl = avatarUrl.trim();
      if (_avatarUrl.isEmpty) {
        await prefs.remove(_kAvatarUrl);
      } else {
        await prefs.setString(_kAvatarUrl, _avatarUrl);
      }
    }
    notifyListeners();
  }

  /// 账号登录成功后调用：保存 userId + Token
  Future<void> setAccountSession({
    required String userId,
    required String accessToken,
    required String refreshToken,
    String? nickname,
    bool? passwordPromptRequired,
  }) async {
    final accountChanged = _userId != null && _userId != userId;
    _userId = userId;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _accountLoginRequired = false;
    _sessionExpired = false;
    if (passwordPromptRequired != null) {
      _passwordPromptRequired = passwordPromptRequired;
    }
    if (nickname != null && nickname.isNotEmpty) _name = nickname;

    final prefs = await SharedPreferences.getInstance();
    if (accountChanged) {
      _avatarUrl = '';
      await prefs.remove(_kAvatarUrl);
    }
    await prefs.setString(_kUserId, userId);
    if (nickname != null && nickname.isNotEmpty) {
      await prefs.setString(_kName, _name);
    }
    await prefs.setBool(_kPasswordPromptRequired, _passwordPromptRequired);
    await prefs.setBool(_kAccountLoginRequired, false);
    await prefs.setBool(_kSessionExpired, false);
    await _secureStorage.write(key: _kAccess, value: accessToken);
    await _secureStorage.write(key: _kRefresh, value: refreshToken);
    notifyListeners();
  }

  Future<void> resolvePasswordPrompt() async {
    _passwordPromptRequired = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPasswordPromptRequired, false);
  }

  /// 退出账号登录（保留本地昵称，仅清除 Token）
  Future<void> signOut({bool sessionExpired = false}) async {
    _userId = null;
    _accessToken = null;
    _refreshToken = null;
    _avatarUrl = '';
    _passwordPromptRequired = false;
    _accountLoginRequired = true;
    _sessionExpired = sessionExpired;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserId);
    await prefs.remove(_kLegacyAccountIdentifier);
    await prefs.remove(_kPasswordPromptRequired);
    await prefs.remove(_kAvatarUrl);
    await prefs.setBool(_kAccountLoginRequired, true);
    await prefs.setBool(_kSessionExpired, sessionExpired);
    await _secureStorage.delete(key: _kAccess);
    await _secureStorage.delete(key: _kRefresh);
    notifyListeners();
  }

  /// 彻底清除（包括本地昵称）
  Future<void> clear({bool allowLocalMode = false}) async {
    _name = '';
    await signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kName);
    if (allowLocalMode) {
      _accountLoginRequired = false;
      await prefs.setBool(_kAccountLoginRequired, false);
    }
    _sessionExpired = false;
    await prefs.setBool(_kSessionExpired, false);
    notifyListeners();
  }
}
