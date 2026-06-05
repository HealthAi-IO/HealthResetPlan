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

  // ── 内存缓存：避免每次进入页面都查后端，减少卡顿 ────────────
  MembershipStatus? _cached;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _cacheTtl = Duration(minutes: 5);

  Future<MembershipStatus> getStatus({bool forceRefresh = false}) async {
    // 仅账号登录后才查询会员状态；本地模式始终视为免费版
    if (!UserSession.instance.isAccountLogin || _client == null) {
      return MembershipStatus.free;
    }

    // 命中缓存且未强制刷新 → 直接返回，避免网络阻塞
    final age = DateTime.now().difference(_cachedAt);
    if (!forceRefresh && _cached != null && age < _cacheTtl) {
      return _cached!;
    }

    try {
      final resp = await _client.dio.get(
        '/membership/status',
        options: Options(
          // 关键：3 秒短超时，网络慢直接降级，不卡 UI
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      final status = MembershipStatus.fromJson(_unwrapData(resp.data));
      _cached = status;
      _cachedAt = DateTime.now();
      return status;
    } on DioException {
      // 网络异常时：若有旧缓存就返回旧值；否则按"未开通"处理
      return _cached ?? MembershipStatus.free;
    }
  }

  Future<bool> isActive() async {
    final status = await getStatus();
    return status.isActive;
  }

  /// 清空缓存（兑换激活码后立即调用，下次查询拿最新状态）
  void invalidateCache() {
    _cached = null;
    _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// 激活码兑换。
  ///
  /// 必须先登录账号才能兑换 — 会员权益与账号绑定，
  /// 服务端记录订阅状态，多端同步可用。
  ///
  /// 成功时正常返回；失败时抛出 [DioException] 携带后端错误信息，
  /// 或 [StateError] 提示需要登录。
  Future<void> activateWithCode(String code) async {
    final normalized = code.toUpperCase().trim();
    if (!UserSession.instance.isAccountLogin || _client == null) {
      throw StateError('请先登录账号后再兑换激活码');
    }
    final resp = await _client.dio.post(
      '/membership/redeem',
      data: {'code': normalized},
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    if (resp.data is Map && resp.data['code'] == 0) {
      invalidateCache();
      return;
    }
    // 后端返回业务错误 — 构造 DioException 携带响应体，由调用方解析
    final options = RequestOptions(path: '/membership/redeem');
    throw DioException(
      requestOptions: options,
      response: Response(
        requestOptions: options,
        statusCode: 200,
        data: resp.data,
      ),
      message: resp.data is Map
          ? resp.data['message']?.toString() ?? '激活失败'
          : '激活失败',
    );
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
