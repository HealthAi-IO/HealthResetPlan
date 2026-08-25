import 'package:flutter/material.dart';

import '../di/service_locator.dart';
import '../network/telemetry_api.dart';

class TelemetryObserver extends NavigatorObserver {
  void _record(Route<dynamic>? route) {
    if (!sl.isRegistered<TelemetryApi>()) return;
    final name = route?.settings.name ?? '';
    final event = switch (name) {
      '/home' => 'home_view',
      '/chat' => 'ai_chat',
      '/plan' => 'plan_view',
      '/meals' => 'meal_view',
      '/records' => 'record_view',
      '/self-check' => 'image_analysis_view',
      '/report' => 'report_recognition_view',
      '/record-history/weekly' => 'weekly_report_view',
      '/quit-smoking' => 'quit_smoking_view',
      '/content' => 'content_view',
      '/messages' => 'message_center_view',
      '/ai-credits' => 'ai_credits_view',
      '/profile' => 'profile_view',
      '/clock' => 'clock_view',
      '/indicators' || '/indicators/input' => 'indicator_view',
      _ => '',
    };
    if (event.isNotEmpty) sl<TelemetryApi>().record(event);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record(newRoute);
}
