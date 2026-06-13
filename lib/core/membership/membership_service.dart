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
      _cached = _cached?.normalized;
      return _cached ?? MembershipStatus.free;
    }
  }

  Future<bool> isActive() async {
    final status = await getStatus();
    return status.isActive;
  }

  void invalidateCache() {
    _cached = null;
    _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

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
