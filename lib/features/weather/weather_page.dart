import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  bool _loading = true;
  String? _error;
  String _locationName = '当前位置';
  _WeatherNow? _now;
  List<_WeatherDay> _days = const [];

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final position = await _currentPosition();
      final placeName = await _placeName(position);
      final response = await Dio().get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'current':
              'temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m',
          'daily':
              'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
          'timezone': 'auto',
          'forecast_days': 7,
        },
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) return;
      setState(() {
        _locationName = placeName;
        _now = _WeatherNow.fromJson(data['current'] as Map);
        _days = _parseDays(data['daily'] as Map);
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
    if (!serviceEnabled) {
      throw StateError('请先开启系统定位服务');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('定位权限未开启');
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
      final name = [
        p.locality,
        p.subLocality,
      ].where((item) => item != null && item.isNotEmpty).join(' ');
      return name.isEmpty ? '当前位置' : name;
    } catch (_) {
      return '当前位置';
    }
  }

  List<_WeatherDay> _parseDays(Map raw) {
    final time = (raw['time'] as List?) ?? const [];
    final max = (raw['temperature_2m_max'] as List?) ?? const [];
    final min = (raw['temperature_2m_min'] as List?) ?? const [];
    final code = (raw['weather_code'] as List?) ?? const [];
    final rain = (raw['precipitation_probability_max'] as List?) ?? const [];
    final count = [
      time.length,
      max.length,
      min.length,
      code.length,
      rain.length
    ].reduce((a, b) => a < b ? a : b);
    return [
      for (var i = 0; i < count; i++)
        _WeatherDay(
          date: DateTime.tryParse(time[i].toString()) ?? DateTime.now(),
          max: ((max[i] ?? 0) as num).round(),
          min: ((min[i] ?? 0) as num).round(),
          code: ((code[i] ?? 0) as num).toInt(),
          rain: ((rain[i] ?? 0) as num).round(),
        ),
    ];
  }

  String _friendlyError(Object error) {
    if (error is StateError) return error.message;
    if (error is DioException) return '天气服务请求失败，请稍后重试';
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('天气')),
      body: RefreshIndicator(
        onRefresh: _loadWeather,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _ErrorCard(message: _error!, onRetry: _loadWeather)
            else ...[
              _NowCard(locationName: _locationName, now: _now!),
              const SizedBox(height: 16),
              for (final day in _days)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DayCard(day: day),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeatherNow {
  const _WeatherNow({
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.code,
  });

  final int temperature;
  final int humidity;
  final int windSpeed;
  final int code;

  factory _WeatherNow.fromJson(Map raw) {
    return _WeatherNow(
      temperature: ((raw['temperature_2m'] ?? 0) as num).round(),
      humidity: ((raw['relative_humidity_2m'] ?? 0) as num).round(),
      windSpeed: ((raw['wind_speed_10m'] ?? 0) as num).round(),
      code: ((raw['weather_code'] ?? 0) as num).toInt(),
    );
  }
}

class _WeatherDay {
  const _WeatherDay({
    required this.date,
    required this.max,
    required this.min,
    required this.code,
    required this.rain,
  });

  final DateTime date;
  final int max;
  final int min;
  final int code;
  final int rain;
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.locationName, required this.now});

  final String locationName;
  final _WeatherNow now;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            locationName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(_weatherIcon(now.code), size: 48, color: AppTheme.deepBlue),
              const SizedBox(width: 14),
              Text(
                '${now.temperature}°',
                style:
                    const TextStyle(fontSize: 42, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _weatherText(now.code),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '湿度 ${now.humidity}%',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                  Text(
                    '风速 ${now.windSpeed} km/h',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});

  final _WeatherDay day;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(DateFormat('MM/dd E').format(day.date)),
          ),
          Icon(_weatherIcon(day.code), color: AppTheme.deepBlue),
          const SizedBox(width: 10),
          Expanded(child: Text(_weatherText(day.code))),
          Text('${day.min}° / ${day.max}°'),
          const SizedBox(width: 12),
          Text('雨 ${day.rain}%', style: const TextStyle(color: AppTheme.muted)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          const Icon(
            Icons.location_off_outlined,
            size: 40,
            color: AppTheme.muted,
          ),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('重新定位')),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: AppTheme.cardBorder),
  );
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
