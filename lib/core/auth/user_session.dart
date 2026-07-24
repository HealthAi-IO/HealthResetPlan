import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户会话。
///
/// 同时支持两种模式：
/// - **本地模式**：仅 [name] 有值，[userId] / [accessToken] 为空，所有数据存本机
/// - **账号模式**：登录后 [userId] / [accessToken] 都有值，可使用在线功能
class UserSession {
  UserSession._();
  static final UserSession instance = UserSession._();

  // 公开存储（昵称）
  static const _kName = 'user_display_name';
  static const _kUserId = 'user_account_id';
  static const _kLegacyAccountIdentifier = 'user_account_identifier';

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
  String? _userId;
  String? _accessToken;
  String? _refreshToken;
  bool _passwordPromptRequired = false;

  String get name => _name;
  String? get userId => _userId;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get passwordPromptRequired => _passwordPromptRequired;

  bool get hasName => _name.isNotEmpty;

  /// 是否已绑定真实账号（拥有 JWT Token）
  bool get isAccountLogin =>
      _userId != null && _accessToken != null && _accessToken!.isNotEmpty;

  /// 启动时调用：从持久化中加载昵称和 Token
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString(_kName) ?? '';
    _userId = prefs.getString(_kUserId);
    await prefs.remove(_kLegacyAccountIdentifier);

    _accessToken = await _secureStorage.read(key: _kAccess);
    _refreshToken = await _secureStorage.read(key: _kRefresh);
    _passwordPromptRequired = prefs.getBool(_kPasswordPromptRequired) ?? false;
  }

  /// 仅设置本地昵称（本地模式）
  Future<void> setName(String name) async {
    _name = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, _name);
  }

  /// 账号登录成功后调用：保存 userId + Token
  Future<void> setAccountSession({
    required String userId,
    required String accessToken,
    required String refreshToken,
    String? nickname,
    bool? passwordPromptRequired,
  }) async {
    _userId = userId;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    if (passwordPromptRequired != null) {
      _passwordPromptRequired = passwordPromptRequired;
    }
    if (nickname != null && nickname.isNotEmpty) _name = nickname;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserId, userId);
    if (nickname != null && nickname.isNotEmpty) {
      await prefs.setString(_kName, _name);
    }
    await prefs.setBool(_kPasswordPromptRequired, _passwordPromptRequired);
    await _secureStorage.write(key: _kAccess, value: accessToken);
    await _secureStorage.write(key: _kRefresh, value: refreshToken);
  }

  Future<void> resolvePasswordPrompt() async {
    _passwordPromptRequired = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPasswordPromptRequired, false);
  }

  /// 退出账号登录（保留本地昵称，仅清除 Token）
  Future<void> signOut() async {
    _userId = null;
    _accessToken = null;
    _refreshToken = null;
    _passwordPromptRequired = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserId);
    await prefs.remove(_kLegacyAccountIdentifier);
    await prefs.remove(_kPasswordPromptRequired);
    await _secureStorage.delete(key: _kAccess);
    await _secureStorage.delete(key: _kRefresh);
  }

  /// 彻底清除（包括本地昵称）
  Future<void> clear() async {
    _name = '';
    await signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kName);
  }
}
