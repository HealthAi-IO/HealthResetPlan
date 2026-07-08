import 'package:flutter/foundation.dart';
import 'package:tobias/tobias.dart';

class AlipayPayService {
  AlipayPayService({Tobias? tobias}) : _tobias = tobias ?? Tobias();

  final Tobias _tobias;

  Future<void> pay(Map<String, dynamic> credential) async {
    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!supported) {
      throw StateError('Alipay only supports Android and iOS');
    }

    final orderString = credential['orderString']?.toString() ?? '';
    if (orderString.isEmpty) {
      throw StateError('Alipay order string is empty');
    }

    final installed = await _tobias.isAliPayInstalled;
    if (!installed) throw StateError('Please install Alipay first');

    final result = await _tobias.pay(orderString);
    final status = result['resultStatus']?.toString() ?? '';
    if (status == '9000') return;
    if (status == '6001') throw StateError('Payment cancelled');
    throw StateError(result['memo']?.toString().isNotEmpty == true
        ? result['memo'].toString()
        : 'Alipay payment failed');
  }
}
