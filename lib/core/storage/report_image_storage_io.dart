import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> persistReportImage(XFile image, String clientId) async {
  final dir = await getApplicationDocumentsDirectory();
  final reportDir = Directory(p.join(dir.path, 'private_reports'));
  await reportDir.create(recursive: true);
  final nameExt = p.extension(image.name);
  final pathExt = p.extension(image.path);
  final ext = (nameExt.isNotEmpty ? nameExt : pathExt).toLowerCase();
  final target = File(
    p.join(reportDir.path, '$clientId${ext.isEmpty ? '.jpg' : ext}'),
  );
  await target.writeAsBytes(await image.readAsBytes(), flush: true);
  return target.path;
}

Future<void> deleteReportImage(String imagePath) async {
  if (imagePath.isEmpty) return;
  final segments = p.normalize(imagePath).split(RegExp(r'[\\/]+'));
  if (!segments.contains('private_reports')) return;
  final file = File(imagePath);
  if (await file.exists()) await file.delete();
}

Future<Uint8List?> readReportImage(String imagePath) async {
  if (imagePath.isEmpty) return null;
  final file = File(imagePath);
  return await file.exists() ? file.readAsBytes() : null;
}

Future<String> restoreReportImage(
  Uint8List bytes,
  String clientId,
  String extension,
) async {
  final dir = await getApplicationDocumentsDirectory();
  final reportDir = Directory(p.join(dir.path, 'private_reports'));
  await reportDir.create(recursive: true);
  final safeExtension = extension.startsWith('.') ? extension : '.$extension';
  final file = File(p.join(reportDir.path, '$clientId$safeExtension'));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

ImageProvider<Object>? reportImageProvider(String imagePath) {
  if (imagePath.isEmpty) return null;
  final file = File(imagePath);
  return file.existsSync() ? FileImage(file) : null;
}
