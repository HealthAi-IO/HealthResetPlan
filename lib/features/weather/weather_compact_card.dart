import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';

class WeatherCompactCard extends StatefulWidget {
  const WeatherCompactCard({super.key});

  @override
  State<WeatherCompactCard> createState() => _WeatherCompactCardState();
}

class _WeatherCompactCardState extends State<WeatherCompactCard> {
  bool _loading = true;
  String? _error;
  String _locationName = '当前位置';
  int _temperature = 0;
  int _code = 0;
  int _rain = 0;
  int _windSpeed = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final position = await _currentPosition();
      final response = await Dio().get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'current': 'temperature_2m,weather_code,wind_speed_10m',
          'daily': 'precipitation_probability_max',
          'timezone': 'auto',
          'forecast_days': 1,
        },
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final current = Map<String, dynamic>.from(data['current'] as Map);
      final daily = Map<String, dynamic>.from(data['daily'] as Map);
      final rainList = daily['precipitation_probability_max'] as List?;
      final place = await _placeName(position);
      if (!mounted) return;
      setState(() {
        _locationName = place;
        _temperature = ((current['temperature_2m'] ?? 0) as num).round();
        _code = ((current['weather_code'] ?? 0) as num).toInt();
        _windSpeed = ((current['wind_speed_10m'] ?? 0) as num).round();
        _rain = rainList == null || rainList.isEmpty
            ? 0
            : ((rainList.first ?? 0) as num).round();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<Position> _currentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw StateError('定位未开启');

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('未授权定位');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  Future<String> _placeName(Position position) async {
    try {
      final places = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (places.isEmpty) return '当前位置';
      final p = places.first;
      final name = [p.locality, p.subLocality]
          .where((item) => item != null && item.isNotEmpty)
          .join(' ');
      return name.isEmpty ? '当前位置' : name;
    } catch (_) {
      return '当前位置';
    }
  }

  String _friendlyError(Object error) {
    if (error is StateError) return error.message;
    return '天气加载失败';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/weather'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE0F2FE), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: _loading
            ? const SizedBox(
                height: 42,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Row(
                    children: [
                      const Icon(Icons.location_off_outlined,
                          color: AppTheme.muted),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!)),
                      TextButton(onPressed: _load, child: const Text('重试')),
                    ],
                  )
                : Row(
                    children: [
                      Icon(_weatherIcon(_code),
                          size: 34, color: AppTheme.deepBlue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$_locationName · ${_weatherText(_code)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '降雨 $_rain% · 风速 $_windSpeed km/h',
                              style: const TextStyle(
                                  color: AppTheme.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$_temperature°',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.deepBlue,
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppTheme.muted),
                    ],
                  ),
      ),
    );
  }
}

IconData _weatherIcon(int code) {
  if (code == 0) return Icons.wb_sunny_outlined;
  if ([1, 2, 3].contains(code)) return Icons.cloud_outlined;
  if ([45, 48].contains(code)) return Icons.foggy;
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
    return Icons.water_drop_outlined;
  }
  if (code >= 71 && code <= 77) return Icons.ac_unit_outlined;
  if (code >= 95) return Icons.thunderstorm_outlined;
  return Icons.cloud_outlined;
}

String _weatherText(int code) {
  if (code == 0) return '晴';
  if (code == 1) return '少云';
  if (code == 2) return '多云';
  if (code == 3) return '阴';
  if ([45, 48].contains(code)) return '雾';
  if (code >= 51 && code <= 67) return '小雨';
  if (code >= 71 && code <= 77) return '降雪';
  if (code >= 80 && code <= 82) return '阵雨';
  if (code >= 95) return '雷雨';
  return '天气';
}
