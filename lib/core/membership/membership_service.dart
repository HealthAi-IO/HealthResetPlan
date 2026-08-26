import '../auth/user_session.dart';
import '../payment/payment_api.dart';

/// Compatibility state for legacy presentation code. Billing is not supported.
class MembershipStatus {
  const MembershipStatus({
    required this.isActive,
    this.planName,
    this.expiresAt,
  });

  final bool isActive;
  final String? planName;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  static const free = MembershipStatus(isActive: false);
}

class MembershipService {
  MembershipService({required PaymentApi api}) : _api = api;

  final PaymentApi _api;

  Future<MembershipStatus> getStatus({bool forceRefresh = false}) async {
    if (!UserSession.instance.isAccountLogin) return MembershipStatus.free;
    try {
      final data = await _api.vipStatus();
      final planName = switch ('${data['plan_code']}') {
        'vip_month' => 'VIP 月卡',
        'vip_quarter' => 'VIP 季卡',
        'vip_year' => 'VIP 年卡',
        _ => null,
      };
      return MembershipStatus(
        isActive: data['active'] == true,
        planName: planName,
        expiresAt: DateTime.tryParse('${data['expires_at'] ?? ''}')?.toLocal(),
      );
    } catch (_) {
      return MembershipStatus.free;
    }
  }

  void invalidateCache() {}
}
