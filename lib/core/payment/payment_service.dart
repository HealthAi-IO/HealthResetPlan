import 'dart:async';

import 'package:alipay_kit/alipay_kit.dart';
import 'package:fluwx/fluwx.dart';

import 'payment_api.dart';

class PaymentService {
  PaymentService({required PaymentApi api}) : _api = api;

  final PaymentApi _api;
  final Fluwx _fluwx = Fluwx();
  StreamSubscription<AlipayResp>? _alipaySubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _alipaySubscription = AlipayKitPlatform.instance.payResp().listen((_) {});
  }

  Future<Map<String, dynamic>> balance() => _api.balance();
  Future<List<Map<String, dynamic>>> products() => _api.products();
  Future<List<Map<String, dynamic>>> ledger() => _api.ledger();
  Future<List<Map<String, dynamic>>> orders() => _api.orders();

  Future<Map<String, dynamic>> purchase({
    required String productCode,
    required String channel,
  }) async {
    final order = await _api.createOrder(
      productCode: productCode,
      channel: channel,
    );
    final payment = Map<String, dynamic>.from(order['payment'] as Map? ?? {});
    if (channel == 'wechat') {
      await _payWechat(payment);
    } else if (channel == 'alipay') {
      await AlipayKitPlatform.instance.pay(
        orderInfo: payment['orderString'] as String? ?? '',
      );
    }
    return _pollOrder(order['orderNo'] as String);
  }

  Future<Map<String, dynamic>> requestRefund(
    String orderNo, {
    required String reason,
  }) =>
      _api.requestRefund(orderNo: orderNo, reason: reason);

  Future<void> _payWechat(Map<String, dynamic> payment) async {
    final appId = payment['appId'] as String?;
    if (appId == null || appId.isEmpty) {
      throw StateError('微信支付参数未配置');
    }
    await _fluwx.registerApi(appId: appId, doOnAndroid: true, doOnIOS: false);
    final started = await _fluwx.pay(
      which: Payment(
        appId: appId,
        partnerId: payment['partnerId'] as String? ?? '',
        prepayId: payment['prepayId'] as String? ?? '',
        packageValue: payment['packageValue'] as String? ?? 'Sign=WXPay',
        nonceStr: payment['nonceStr'] as String? ?? '',
        timestamp: int.tryParse('${payment['timeStamp']}') ?? 0,
        sign: payment['sign'] as String? ?? '',
      ),
    );
    if (!started) throw StateError('微信支付未能启动');
  }

  Future<Map<String, dynamic>> _pollOrder(String orderNo) async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final status = await _api.orderStatus(orderNo);
      if (status['status'] == 'paid' ||
          status['status'] == 'expired' ||
          status['status'] == 'failed' ||
          status['status'] == 'refunded') {
        return status;
      }
    }
    return _api.orderStatus(orderNo);
  }

  Future<void> dispose() =>
      _alipaySubscription?.cancel() ?? Future<void>.value();
}
