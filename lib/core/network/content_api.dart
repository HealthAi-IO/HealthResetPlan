import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/user_session.dart';
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

  Future<ContentInteraction> contentInteraction(int id) async {
    try {
      return ContentInteraction.fromJson(
        await _getData('/content/$id/interactions'),
      );
    } catch (_) {
      if (!kDebugMode) rethrow;
      return _localInteraction(id);
    }
  }

  Future<ContentInteraction> reactToContent(int id, String reaction) async {
    try {
      final response = await _client.dio.put(
        '/content/$id/reaction',
        data: {'reaction': reaction},
      );
      return ContentInteraction.fromJson(_responseData(response.data));
    } catch (_) {
      if (!kDebugMode) rethrow;
      return _setLocalReaction(id, reaction);
    }
  }

  Future<ContentInteraction> addComment(int id, String content) async {
    try {
      final response = await _client.dio.post(
        '/content/$id/comments',
        data: {'content': content},
      );
      return ContentInteraction.fromJson(_responseData(response.data));
    } catch (_) {
      if (!kDebugMode) rethrow;
      return _addLocalComment(id, content);
    }
  }

  Future<ContentInteraction> deleteComment(int id, int commentId) async {
    try {
      final response = await _client.dio.delete(
        '/content/$id/comments/$commentId',
      );
      return ContentInteraction.fromJson(_responseData(response.data));
    } catch (_) {
      if (!kDebugMode) rethrow;
      return _deleteLocalComment(id, commentId);
    }
  }

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
    if (value.isEmpty) return value;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      return uri.scheme == 'https' ? value : '';
    }
    return Uri.parse(_client.dio.options.baseUrl).resolve(value).toString();
  }

  Uri get apiBaseUri => Uri.parse(_client.dio.options.baseUrl);

  Future<Map<String, dynamic>> _getData(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _client.dio.get(path, queryParameters: query);
    return _responseData(response.data);
  }

  Map<String, dynamic> _responseData(Object? body) {
    if (body is Map) return Map<String, dynamic>.from(body);
    throw const FormatException('内容接口响应格式异常');
  }

  Future<ContentInteraction> _localInteraction(int id) async {
    return ContentInteraction.fromJson(await _localData(id));
  }

  Future<ContentInteraction> _setLocalReaction(int id, String reaction) async {
    final data = await _localData(id);
    final previous = '${data['userReaction'] ?? ''}';
    var likes = _int(data['likeCount']);
    var dislikes = _int(data['dislikeCount']);
    if (previous == 'like') likes = (likes - 1).clamp(0, likes);
    if (previous == 'dislike') dislikes = (dislikes - 1).clamp(0, dislikes);
    if (reaction == 'like') likes++;
    if (reaction == 'dislike') dislikes++;
    data
      ..['likeCount'] = likes
      ..['dislikeCount'] = dislikes
      ..['userReaction'] = reaction;
    await _saveLocalData(id, data);
    return ContentInteraction.fromJson(data);
  }

  Future<ContentInteraction> _addLocalComment(int id, String content) async {
    final data = await _localData(id);
    final comments = List<Map<String, dynamic>>.from(
      (data['comments'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    comments.insert(0, {
      'id': DateTime.now().microsecondsSinceEpoch,
      'authorName': UserSession.instance.name.trim().isEmpty
          ? '健康用户'
          : UserSession.instance.name.trim(),
      'content': content,
      'createdAt': DateTime.now().toIso8601String(),
      'isMine': true,
    });
    data['comments'] = comments;
    await _saveLocalData(id, data);
    return ContentInteraction.fromJson(data);
  }

  Future<ContentInteraction> _deleteLocalComment(
    int id,
    int commentId,
  ) async {
    final data = await _localData(id);
    final comments = List<Map<String, dynamic>>.from(
      (data['comments'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    )..removeWhere((comment) => _int(comment['id']) == commentId);
    data['comments'] = comments;
    await _saveLocalData(id, data);
    return ContentInteraction.fromJson(data);
  }

  Future<Map<String, dynamic>> _localData(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('debug_content_interaction_$id');
    if (raw == null) {
      return {
        'likeCount': 0,
        'dislikeCount': 0,
        'userReaction': '',
        'comments': <Map<String, dynamic>>[],
      };
    }
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  Future<void> _saveLocalData(int id, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('debug_content_interaction_$id', jsonEncode(data));
  }

  int _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
