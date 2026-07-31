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
    final extension = file.name.toLowerCase().split('.').last;
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => file.mimeType ?? 'application/octet-stream',
    };
    return _upload(
      file,
      clientId,
      '/files/upload',
      contentType: contentType,
      queryParameters: const {'kind': 'image'},
    );
  }

  Future<String> _upload(
    XFile file,
    String clientId,
    String path, {
    String? contentType,
    Map<String, dynamic>? queryParameters,
  }) async {
    final form = FormData.fromMap({
      'clientId': clientId,
      'file': MultipartFile.fromBytes(
        await file.readAsBytes(),
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
    final body = response.data;
    if (body is Map && body['code'] == 0 && body['data'] is Map) {
      return '${(body['data'] as Map)['objectKey'] ?? ''}';
    }
    throw StateError('${body is Map ? body['message'] : '文件上传失败'}');
  }

  Future<void> delete(String objectKey) async {
    if (objectKey.isEmpty) return;
    await _client.dio.delete(
      '/files',
      queryParameters: {'objectKey': objectKey},
    );
  }
}
