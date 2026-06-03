import 'package:shared_preferences/shared_preferences.dart';

class MembershipStatus {
  const MembershipStatus({
    required this.isActive,
    this.planCode,
    this.planName,
    this.expiresAt,
  });

  final bool isActive;
  final String? planCode;
  final String? planName;
  final DateTime? expiresAt;

  static const MembershipStatus free = MembershipStatus(isActive: false);
}

/// 本地会员状态管理服务。
///
/// 数据存储在 SharedPreferences；激活码兑换或未来对接支付成功后调用 [activate]。
class MembershipService {
  static const _kActive = 'member_active';
  static const _kPlanCode = 'member_plan_code';
  static const _kPlanName = 'member_plan_name';
  static const _kExpiresAtMs = 'member_expires_at_ms';

  // 激活码 → 有效天数（用于测试和管理员开通）
  static const Map<String, int> _promoCodes = {
    'HEALTH30': 30,
    'HEALTH365': 365,
    'VIP30': 30,
    'VIP365': 365,
    'TRIAL7': 7,
  };

  Future<MembershipStatus> getStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool(_kActive) ?? false;
    if (!active) return MembershipStatus.free;

    final expiresMs = prefs.getInt(_kExpiresAtMs) ?? 0;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresMs);
    if (expiresAt.isBefore(DateTime.now())) {
      await _clear(prefs);
      return MembershipStatus.free;
    }

    return MembershipStatus(
      isActive: true,
      planCode: prefs.getString(_kPlanCode),
      planName: prefs.getString(_kPlanName),
      expiresAt: expiresAt,
    );
  }

  Future<bool> isActive() async {
    final s = await getStatus();
    return s.isActive;
  }

  /// 用激活码兑换，返回 false 表示无效码。
  Future<bool> activateWithCode(String code) async {
    final days = _promoCodes[code.toUpperCase().trim()];
    if (days == null) return false;
    final planCode = days >= 300 ? 'yearly' : days >= 25 ? 'monthly' : 'trial';
    final planName = days >= 300 ? '年度会员' : days >= 25 ? '月度会员' : '体验会员';
    await activate(planCode: planCode, planName: planName, days: days);
    return true;
  }

  Future<void> activate({
    required String planCode,
    required String planName,
    required int days,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // 若当前已是会员且未过期，从当前到期日累加
    final current = await getStatus();
    final base = (current.isActive && current.expiresAt != null)
        ? current.expiresAt!
        : DateTime.now();
    final expires = base.add(Duration(days: days));

    await prefs.setBool(_kActive, true);
    await prefs.setString(_kPlanCode, planCode);
    await prefs.setString(_kPlanName, planName);
    await prefs.setInt(_kExpiresAtMs, expires.millisecondsSinceEpoch);
  }

  Future<void> deactivate() async {
    final prefs = await SharedPreferences.getInstance();
    await _clear(prefs);
  }

  Future<void> _clear(SharedPreferences prefs) async {
    await Future.wait([
      prefs.remove(_kActive),
      prefs.remove(_kPlanCode),
      prefs.remove(_kPlanName),
      prefs.remove(_kExpiresAtMs),
    ]);
  }
}
