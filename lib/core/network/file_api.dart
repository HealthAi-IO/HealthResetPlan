import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';

class FileApi {
  FileApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<String> upload(XFile file, String clientId) async {
    return _upload(file, clientId, '/files/upload');
  }

  Future<String> uploadImage(XFile file, String clientId) async {
    final bytes = await file.readAsBytes();
    final contentType = detectImageMimeType(bytes) ?? _nameMimeType(file);
    return _upload(
      file,
      clientId,
      '/files/upload',
      bytes: bytes,
      contentType: contentType,
      queryParameters: const {'kind': 'image'},
    );
  }

  static String? detectImageMimeType(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  Future<String> _upload(
    XFile file,
    String clientId,
    String path, {
    List<int>? bytes,
    String? contentType,
    Map<String, dynamic>? queryParameters,
  }) async {
    final form = FormData.fromMap({
      'clientId': clientId,
      'file': MultipartFile.fromBytes(
        bytes ?? await file.readAsBytes(),
        filename: file.name,
        contentType: DioMediaType.parse(
          contentType ?? file.mimeType ?? 'application/octet-stream',
        ),
      ),
    });
    final response = await _client.dio.post(
      path,
      data: form,
      queryParameters: queryParameters,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = response.data;
    if (data is Map) return '${data['objectKey'] ?? ''}';
    throw const FormatException('文件上传响应格式异常');
  }

  String _nameMimeType(XFile file) {
    final extension = file.name.toLowerCase().split('.').last;
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => file.mimeType ?? 'application/octet-stream',
    };
  }

  Future<void> delete(String objectKey) async {
    if (objectKey.isEmpty) return;
    await _client.dio.delete(
      '/files',
      queryParameters: {'objectKey': objectKey},
    );
  }
}
