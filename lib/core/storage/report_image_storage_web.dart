import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/user_session.dart';
import '../config/app_config.dart';

Future<String> persistReportImage(XFile image, String clientId) async {
  throw UnsupportedError('文件必须通过在线文件接口上传');
}

Future<void> deleteReportImage(String imagePath) async {}

Future<Uint8List?> readReportImage(String imagePath) async => null;

Future<String> restoreReportImage(
  Uint8List bytes,
  String clientId,
  String extension,
) async {
  throw UnsupportedError('不支持恢复本地文件');
}

ImageProvider<Object>? reportImageProvider(String objectKey) {
  if (!objectKey.startsWith('files/')) return null;
  return NetworkImage(
    '${apiUrl('files/content')}'
    '?objectKey=${Uri.encodeQueryComponent(objectKey)}',
    headers: {
      if (UserSession.instance.accessToken != null)
        'Authorization': 'Bearer ${UserSession.instance.accessToken}',
    },
  );
}
