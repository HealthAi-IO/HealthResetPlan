import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_reset_plan/core/auth/user_session.dart';
import 'package:health_reset_plan/core/di/service_locator.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:health_reset_plan/features/routine/routine_poster.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSession.instance.setAccountDisplay(avatarUrl: '');
  });
  tearDown(() => sl.reset());

  testWidgets('missing avatar gives feedback without enabling the switch',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: RoutinePoster(event: {
      'eventType': 'wake',
      'occurredAt': '2026-10-20T00:00:00Z',
      'quote': '规律地照顾自己',
      'source': 'live',
    })));
    final toggle = find.widgetWithText(SwitchListTile, '海报显示头像');
    await tester.scrollUntilVisible(toggle, 300);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('请先在个人资料中设置头像，再开启海报头像'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in ['valid', 'corrupt', 'network']) {
    testWidgets('avatar handles $scenario response', (tester) async {
      await UserSession.instance
          .setAccountDisplay(avatarUrl: '/files/avatar?objectKey=test-avatar');
      final client = ApiClient();
      final imageBytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(1, 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      sl.registerSingleton<ApiClient>(client);
      client.dio.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) {
        expect(request.path, '/files/avatar');
        expect(request.queryParameters['objectKey'], 'test-avatar');
        if (scenario == 'network') {
          handler.reject(DioException(
              requestOptions: request, type: DioExceptionType.connectionError));
        } else {
          handler.resolve(Response<List<int>>(
              requestOptions: request,
              data: scenario == 'valid' ? imageBytes : [1, 2, 3]));
        }
      }));
      await tester.pumpWidget(const MaterialApp(
          home: RoutinePoster(event: {
        'eventType': 'bed',
        'occurredAt': '2026-10-20T15:00:00Z',
        'quote': '安心休息',
        'source': 'live',
      })));
      final toggle = find.widgetWithText(SwitchListTile, '海报显示头像');
      await tester.scrollUntilVisible(toggle, 300);
      await tester.drag(find.byType(ListView), const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(toggle);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, scenario == 'valid');
      if (scenario != 'valid') {
        expect(find.text('头像暂时不可用，可继续保存海报'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
