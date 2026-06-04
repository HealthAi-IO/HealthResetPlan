import 'package:dio/dio.dart';

import '../auth/user_session.dart';
import '../network/api_client.dart';

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

  factory MembershipStatus.fromJson(Map<String, dynamic> json) {
    final expiresText = json['expiresAt'] as String?;
    return MembershipStatus(
      isActive: json['active'] == true,
      planCode: json['planCode'] as String?,
      planName: json['planName'] as String?,
      expiresAt: expiresText == null ? null : DateTime.tryParse(expiresText),
    );
  }
}

class MembershipService {
  MembershipService({ApiClient? client}) : _client = client;

  final ApiClient? _client;

  Future<MembershipStatus> getStatus() async {
    // 仅账号登录后才查询会员状态；本地模式始终视为免费版
    if (UserSession.instance.isAccountLogin && _client != null) {
      try {
        final resp = await _client.dio.get('/membership/status');
        return MembershipStatus.fromJson(_unwrapData(resp.data));
      } on DioException {
        // 网络异常时不报错，按"未开通"处理
        return MembershipStatus.free;
      }
    }
    return MembershipStatus.free;
  }

  Future<bool> isActive() async {
    final status = await getStatus();
    return status.isActive;
  }

  /// 激活码兑换。
  ///
  /// 必须先登录账号才能兑换 — 会员权益与账号绑定，
  /// 服务端记录订阅状态，多端同步可用。
  Future<bool> activateWithCode(String code) async {
    final normalized = code.toUpperCase().trim();
    if (!UserSession.instance.isAccountLogin || _client == null) {
      throw StateError('请先登录账号后再兑换激活码');
    }
    try {
      final resp = await _client.dio.post(
        '/membership/redeem',
        data: {'code': normalized},
      );
      return (resp.data is Map && resp.data['code'] == 0);
    } on DioException {
      rethrow;
    }
  }

  /// 调试：清空本地状态。会员状态实际由服务端管理，此方法主要为测试用。
  Future<void> deactivate() async {
    // 当前会员状态完全来自服务端，本地无需清理
  }

  Map<String, dynamic> _unwrapData(dynamic body) {
    if (body is! Map) return <String, dynamic>{};
    final code = body['code'];
    if (code != null && code != 0) {
      final options = RequestOptions(path: '/membership/status');
      throw DioException(
        requestOptions: options,
        response: Response(requestOptions: options, data: body),
        message: body['message']?.toString() ?? '会员状态获取失败',
      );
    }
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
