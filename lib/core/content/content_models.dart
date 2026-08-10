class ContentSummary {
  const ContentSummary({
    required this.id,
    required this.type,
    required this.title,
    required this.summary,
    required this.coverUrl,
    required this.publishedAt,
    required this.read,
  });

  factory ContentSummary.fromJson(Map<String, dynamic> json) {
    return ContentSummary(
      id: _int(json['id']),
      type: '${json['type'] ?? ''}',
      title: '${json['title'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      coverUrl: '${json['coverUrl'] ?? ''}',
      publishedAt: _date(json['publishedAt']),
      read: json['read'] == true || json['read'] == 1,
    );
  }

  final int id;
  final String type;
  final String title;
  final String summary;
  final String coverUrl;
  final DateTime? publishedAt;
  final bool read;
}

class ContentDetail {
  const ContentDetail({
    required this.id,
    required this.type,
    required this.title,
    required this.summary,
    required this.coverUrl,
    required this.bodyHtml,
    required this.content,
    required this.sourceType,
    required this.publishedAt,
  });

  factory ContentDetail.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'];
    return ContentDetail(
      id: _int(json['id']),
      type: '${json['type'] ?? ''}',
      title: '${json['title'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      coverUrl: '${json['coverUrl'] ?? ''}',
      bodyHtml: '${json['bodyHtml'] ?? ''}',
      content:
          rawContent is Map ? Map<String, dynamic>.from(rawContent) : const {},
      sourceType: '${json['sourceType'] ?? ''}',
      publishedAt: _date(json['publishedAt']),
    );
  }

  final int id;
  final String type;
  final String title;
  final String summary;
  final String coverUrl;
  final String bodyHtml;
  final Map<String, dynamic> content;
  final String sourceType;
  final DateTime? publishedAt;

  String get lead => '${content['lead'] ?? ''}';
  String get tip => '${content['tip'] ?? ''}';
  List<String> get points => (content['points'] as List? ?? const [])
      .map((value) => '$value')
      .toList();
}

class ContentInteraction {
  const ContentInteraction({
    required this.likeCount,
    required this.dislikeCount,
    required this.userReaction,
    required this.comments,
  });

  factory ContentInteraction.fromJson(Map<String, dynamic> json) {
    return ContentInteraction(
      likeCount: _int(json['likeCount']),
      dislikeCount: _int(json['dislikeCount']),
      userReaction: '${json['userReaction'] ?? ''}',
      comments: (json['comments'] as List? ?? const [])
          .whereType<Map>()
          .map((item) =>
              ContentComment.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  final int likeCount;
  final int dislikeCount;
  final String userReaction;
  final List<ContentComment> comments;
}

class ContentComment {
  const ContentComment({
    required this.id,
    required this.authorName,
    required this.content,
    required this.createdAt,
    required this.isMine,
  });

  factory ContentComment.fromJson(Map<String, dynamic> json) {
    return ContentComment(
      id: _int(json['id']),
      authorName: '${json['authorName'] ?? '健康用户'}',
      content: '${json['content'] ?? ''}',
      createdAt: _date(json['createdAt']),
      isMine: json['isMine'] == true || json['isMine'] == 1,
    );
  }

  final int id;
  final String authorName;
  final String content;
  final DateTime? createdAt;
  final bool isMine;
}

class SiteMessage {
  const SiteMessage({
    required this.id,
    required this.contentId,
    required this.title,
    required this.body,
    required this.read,
    required this.contentStatus,
    required this.createdAt,
  });

  factory SiteMessage.fromJson(Map<String, dynamic> json) {
    return SiteMessage(
      id: _int(json['id']),
      contentId: json['contentId'] == null ? null : _int(json['contentId']),
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
      read: json['status'] == 'read',
      contentStatus: '${json['contentStatus'] ?? 'offline'}',
      createdAt: _date(json['createdAt']),
    );
  }

  final int id;
  final int? contentId;
  final String title;
  final String body;
  final bool read;
  final String contentStatus;
  final DateTime? createdAt;
}

class ContentPage<T> {
  const ContentPage({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  final List<T> items;
  final int total;
  final int page;
  final int size;
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

DateTime? _date(Object? value) {
  final text = '${value ?? ''}';
  return text.isEmpty ? null : DateTime.tryParse(text);
}
