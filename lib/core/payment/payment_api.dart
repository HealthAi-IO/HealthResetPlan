import '../network/api_client.dart';

class PaymentApi {
  PaymentApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> products() async {
    final response = await _client.dio.get('/ai-credits/products');
    return _list(response.data);
  }

  Future<Map<String, dynamic>> balance() async {
    final response = await _client.dio.get('/ai-credits/balance');
    return _map(response.data);
  }

  Future<List<Map<String, dynamic>>> ledger() async {
    final response = await _client.dio.get('/ai-credits/ledger');
    return _list(response.data);
  }

  Future<Map<String, dynamic>> createOrder({
    required String productCode,
    required String channel,
  }) async {
    final response = await _client.dio.post('/ai-credits/orders', data: {
      'productCode': productCode,
      'channel': channel,
    });
    return _map(response.data);
  }

  Future<Map<String, dynamic>> orderStatus(String orderNo) async {
    final response = await _client.dio.get('/ai-credits/orders/$orderNo');
    return _map(response.data);
  }

  Future<Map<String, dynamic>> requestRefund({
    required String orderNo,
    String? reason,
  }) async {
    final response = await _client.dio.post('/ai-credits/refunds', data: {
      'orderNo': orderNo,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    return _map(response.data);
  }

  List<Map<String, dynamic>> _list(Object? value) =>
      (value is List ? value : const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}
