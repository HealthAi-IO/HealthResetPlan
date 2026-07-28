import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

const int syncImageMaxBytes = 500 * 1024;
const int syncImageMaxDimension = 1600;
const int syncImageJpegQuality = 75;

Future<Uint8List?> compressSyncImage(Uint8List bytes) {
  return compute(_compressSyncImage, bytes);
}

Uint8List? _compressSyncImage(Uint8List bytes) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) return null;

  var resized = image.bakeOrientation(decoded);
  final longestSide =
      resized.width > resized.height ? resized.width : resized.height;
  if (longestSide > syncImageMaxDimension) {
    resized = resized.width >= resized.height
        ? image.copyResize(resized, width: syncImageMaxDimension)
        : image.copyResize(resized, height: syncImageMaxDimension);
  }

  var encoded = image.encodeJpg(resized, quality: syncImageJpegQuality);
  while (encoded.length > syncImageMaxBytes &&
      (resized.width > 640 || resized.height > 640)) {
    resized = image.copyResize(
      resized,
      width: (resized.width * 0.85).round(),
      height: (resized.height * 0.85).round(),
    );
    encoded = image.encodeJpg(resized, quality: syncImageJpegQuality);
  }
  return Uint8List.fromList(encoded);
}
