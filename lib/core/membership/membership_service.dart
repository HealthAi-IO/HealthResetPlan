import '../auth/user_session.dart';

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

  bool get isExpired => false;

  static const free = MembershipStatus(isActive: false);
}

class MembershipService {
  MembershipService({Object? client});

  Future<MembershipStatus> getStatus({bool forceRefresh = false}) async =>
      MembershipStatus(isActive: UserSession.instance.isAccountLogin);

  void invalidateCache() {}
}
