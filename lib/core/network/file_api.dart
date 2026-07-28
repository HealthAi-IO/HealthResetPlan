import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';

class FileApi {
  FileApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<String> upload(XFile file, String clientId) async {
    final form = FormData.fromMap({
      'clientId': clientId,
      'file': MultipartFile.fromBytes(
        await file.readAsBytes(),
        filename: file.name,
        contentType: DioMediaType.parse(file.mimeType ?? 'application/octet-stream'),
      ),
    });
    final response = await _client.dio.post(
      '/files/upload',
      data: form,
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
