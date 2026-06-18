import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

Future<String> persistReportImage(XFile image, String clientId) async {
  final bytes = await image.readAsBytes();
  return 'data:${_mimeType(image.name)};base64,${base64Encode(bytes)}';
}

Future<void> deleteReportImage(String imagePath) async {}

Future<Uint8List?> readReportImage(String imagePath) async {
  final comma = imagePath.indexOf(',');
  if (!imagePath.startsWith('data:') || comma < 0) return null;
  return base64Decode(imagePath.substring(comma + 1));
}

Future<String> restoreReportImage(
  Uint8List bytes,
  String clientId,
  String extension,
) async {
  return 'data:${_mimeType(extension)};base64,${base64Encode(bytes)}';
}

ImageProvider<Object>? reportImageProvider(String imagePath) {
  if (imagePath.isEmpty) return null;
  final comma = imagePath.indexOf(',');
  if (imagePath.startsWith('data:') && comma >= 0) {
    return MemoryImage(base64Decode(imagePath.substring(comma + 1)));
  }
  return NetworkImage(imagePath);
}

String _mimeType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
