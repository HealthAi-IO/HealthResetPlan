import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/sync/sync_image_compressor.dart';
import 'package:image/image.dart' as image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sync image is converted to a bounded JPEG', () async {
    final source = image.Image(width: 2400, height: 1800);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }

    final compressed = await compressSyncImage(
      Uint8List.fromList(image.encodePng(source)),
    );
    final decoded = image.decodeJpg(compressed!);

    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(syncImageMaxDimension));
    expect(decoded.height, lessThanOrEqualTo(syncImageMaxDimension));
    expect(compressed.length, lessThanOrEqualTo(syncImageMaxBytes));
  });
}
