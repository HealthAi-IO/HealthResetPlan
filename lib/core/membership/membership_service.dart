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

  static const free = MembershipStatus(isActive: false);

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  MembershipStatus get normalized {
    if (!isActive || !isExpired) return this;
    return MembershipStatus(
      isActive: false,
      planCode: planCode,
      planName: planName,
      expiresAt: expiresAt,
    );
  }

  factory MembershipStatus.fromJson(Map<String, dynamic> json) {
    final expiresText = json['expiresAt'] as String?;
    return MembershipStatus(
      isActive: json['active'] == true,
      planCode: json['planCode'] as String?,
      planName: json['planName'] as String?,
      expiresAt: expiresText == null ? null : DateTime.tryParse(expiresText),
    ).normalized;
  }
}

class MembershipOrder {
  const MembershipOrder({
    required this.orderNo,
    required this.planCode,
    required this.amountFen,
    required this.channel,
    required this.payCredential,
  });

  final String orderNo;
  final String planCode;
  final int amountFen;
  final String channel;
  final Map<String, dynamic> payCredential;

  factory MembershipOrder.fromJson(Map<String, dynamic> json) {
    final credential = json['payCredential'];
    return MembershipOrder(
      orderNo: json['orderNo']?.toString() ?? '',
      planCode: json['planCode']?.toString() ?? '',
      amountFen: (json['amountFen'] as num?)?.toInt() ?? 0,
      channel: json['channel']?.toString() ?? '',
      payCredential: credential is Map
          ? Map<String, dynamic>.from(credential)
          : <String, dynamic>{},
    );
  }
}

class MembershipService {
  MembershipService({ApiClient? client}) : _client = client;

  final ApiClient? _client;

  MembershipStatus? _cached;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _cacheTtl = Duration(minutes: 5);

  Future<MembershipStatus> getStatus({bool forceRefresh = false}) async {
    if (!UserSession.instance.isAccountLogin || _client == null) {
      invalidateCache();
      return MembershipStatus.free;
    }

    final age = DateTime.now().difference(_cachedAt);
    if (!forceRefresh && _cached != null && age < _cacheTtl) {
      _cached = _cached!.normalized;
      return _cached!;
    }

    try {
      final resp = await _client.dio.get(
        '/membership/status',
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      final status = MembershipStatus.fromJson(_unwrapData(resp.data));
      _cached = status;
      _cachedAt = DateTime.now();
      return status;
    } on DioException catch (e) {
      if (_isMembershipInactive(e)) {
        _cached = MembershipStatus.free;
        _cachedAt = DateTime.now();
        return MembershipStatus.free;
      }
      return _cached?.normalized ?? MembershipStatus.free;
    }
  }

  Future<bool> isActive() async => (await getStatus()).isActive;

  void invalidateCache() {
    _cached = null;
    _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> activateWithCode(String code) async {
    if (!UserSession.instance.isAccountLogin || _client == null) {
      throw StateError('请先登录账号后再兑换激活码');
    }
    final resp = await _client.dio.post(
      '/membership/redeem',
      data: {'code': code.toUpperCase().trim()},
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    _unwrapData(resp.data);
    invalidateCache();
  }

  Future<MembershipOrder> createOrder({
    required String planCode,
    String channel = 'wechat',
  }) async {
    if (!UserSession.instance.isAccountLogin || _client == null) {
      throw StateError('请先登录账号后再开通会员');
    }
    final resp = await _client.dio.post(
      '/membership/orders',
      data: {'planCode': planCode, 'channel': channel},
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    return MembershipOrder.fromJson(_unwrapData(resp.data));
  }

  Future<void> deactivate() async {
    _cached = MembershipStatus.free;
    _cachedAt = DateTime.now();
  }

  bool _isMembershipInactive(DioException e) {
    final body = e.response?.data;
    if (body is! Map) return false;
    final code = (body['code'] as num?)?.toInt();
    return code == 40301 || code == 40302;
  }

  Map<String, dynamic> _unwrapData(dynamic body) {
    if (body is! Map) return <String, dynamic>{};
    final code = body['code'];
    if (code != null && code != 0) {
      final options = RequestOptions(path: '/membership');
      throw DioException(
        requestOptions: options,
        response: Response(requestOptions: options, data: body),
        message: body['message']?.toString() ?? '会员请求失败',
      );
    }
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
