import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/content/content_models.dart';

void main() {
  test('评论解析头像地址', () {
    final comment = ContentComment.fromJson(const {
      'id': 1,
      'authorName': '小彤',
      'avatarUrl':
          '/api/v1/files/content?objectKey=avatars%2Fuser-1%2Fa.jpg.enc',
      'content': '很好',
      'isMine': true,
    });

    expect(
      comment.avatarUrl,
      '/api/v1/files/content?objectKey=avatars%2Fuser-1%2Fa.jpg.enc',
    );
  });
}
