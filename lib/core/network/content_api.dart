import '../content/content_models.dart';
import 'api_client.dart';

class ContentApi {
  ContentApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<ContentPage<ContentSummary>> listContent({
    int page = 1,
    int size = 12,
    String? type,
  }) async {
    final data = await _getData(
      '/content',
      query: {
        'page': page,
        'size': size,
        if (type != null && type.isNotEmpty) 'type': type,
      },
    );
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ContentSummary.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return ContentPage(
      items: items,
      total: _int(data['total']),
      page: _int(data['page']),
      size: _int(data['size']),
    );
  }

  Future<ContentDetail> contentDetail(int id) async {
    return ContentDetail.fromJson(await _getData('/content/$id'));
  }

  Future<void> markContentRead(int id) => _client.dio.post('/content/$id/read');

  Future<ContentPage<SiteMessage>> listMessages({
    int page = 1,
    int size = 20,
  }) async {
    final data = await _getData(
      '/messages',
      query: {'page': page, 'size': size},
    );
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => SiteMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return ContentPage(
      items: items,
      total: _int(data['total']),
      page: _int(data['page']),
      size: _int(data['size']),
    );
  }

  Future<int> unreadCount() async {
    final data = await _getData('/messages/unread-count');
    return _int(data['count']);
  }

  Future<void> markMessageRead(int id) =>
      _client.dio.post('/messages/$id/read');

  Future<void> markAllMessagesRead() => _client.dio.post('/messages/read-all');

  String assetUrl(String value) {
    if (value.isEmpty ||
        value.startsWith('http://') ||
        value.startsWith('https://')) {
      return value;
    }
    return Uri.parse(_client.dio.options.baseUrl).resolve(value).toString();
  }

  Uri get apiBaseUri => Uri.parse(_client.dio.options.baseUrl);

  Future<Map<String, dynamic>> _getData(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _client.dio.get(path, queryParameters: query);
    final body = response.data;
    if (body is Map && body['code'] == 0 && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw StateError('${body is Map ? body['message'] : '请求失败'}');
  }

  int _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
