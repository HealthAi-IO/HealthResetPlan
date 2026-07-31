import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/content/content_models.dart';

void main() {
  test('content summary parses server read state', () {
    final item = ContentSummary.fromJson({
      'id': 12,
      'type': 'card',
      'title': '健康科普',
      'summary': '摘要',
      'coverUrl': '',
      'read': 1,
      'publishedAt': '2026-07-31T09:00:00',
    });

    expect(item.id, 12);
    expect(item.read, isTrue);
    expect(item.publishedAt, isNotNull);
  });

  test('card content parses point list', () {
    final item = ContentDetail.fromJson({
      'id': 3,
      'type': 'card',
      'title': '标题',
      'summary': '摘要',
      'content': {
        'lead': '导语',
        'points': ['第一条', '第二条'],
        'tip': '贴士',
      },
    });

    expect(item.points, ['第一条', '第二条']);
    expect(item.tip, '贴士');
  });
}
