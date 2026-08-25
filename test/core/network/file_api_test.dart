import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/network/file_api.dart';

void main() {
  test('按文件签名识别常见图片类型', () {
    expect(
      FileApi.detectImageMimeType([0xff, 0xd8, 0xff]),
      'image/jpeg',
    );
    expect(
      FileApi.detectImageMimeType([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
      'image/png',
    );
    expect(
      FileApi.detectImageMimeType([
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x45,
        0x42,
        0x50,
      ]),
      'image/webp',
    );
  });

  test('不支持的文件签名返回空值', () {
    expect(FileApi.detectImageMimeType([0, 1, 2]), isNull);
  });
}
