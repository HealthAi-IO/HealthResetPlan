import 'package:uuid/uuid.dart';
import '../../core/network/api_client.dart';

DateTime beijingTime(DateTime value) =>
    value.toUtc().add(const Duration(hours: 8));
String routineDate(DateTime value) =>
    beijingTime(value).toIso8601String().substring(0, 10);

class RoutineService {
  RoutineService(this.client);
  final ApiClient client;
  final Map<String, String> _requests = {};

  Future<Map<String, dynamic>> load(
      {int days = 7, String? from, String? to}) async {
    final response = await client.dio.get('/routine', queryParameters: {
      'days': days,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> history([String? before]) async {
    final response = await client.dio.get('/routine/history', queryParameters: {
      if (before != null) 'before': before,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> checkIn(String type, {DateTime? at}) async {
    final key =
        '$type:${at?.toUtc().toIso8601String() ?? routineDate(DateTime.now())}';
    final response = await client.dio.post('/routine/events', data: {
      'eventType': type,
      'requestId': _requests.putIfAbsent(key, () => const Uuid().v4()),
      if (at != null) 'occurredAt': at.toUtc().toIso8601String(),
    });
    _requests.remove(key);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> edit(
      Map event, DateTime at, double? hours, String? quality) async {
    await client.dio.put('/routine/events/${event['id']}', data: {
      'version': event['version'],
      'occurredAt': at.toUtc().toIso8601String(),
      'selfReportedHours': hours,
      'quality': quality,
    });
  }

  Future<void> delete(Map event) async {
    await client.dio.delete('/routine/events/${event['id']}',
        queryParameters: {'version': event['version']});
  }

  Future<void> settings(Map<String, dynamic> settings) async {
    await client.dio.put('/routine/settings', data: settings);
  }
}
