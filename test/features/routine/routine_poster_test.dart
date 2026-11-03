import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  for (final type in ['wake', 'bed']) {
    testWidgets(
        '$type prepares three decoded images and switches without waiting for more network',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await UserSession.instance.setAccountSession(
          userId: 'poster-speed-test',
          accessToken: 'test',
          refreshToken: 'test');
      addTearDown(() => UserSession.instance.signOut());
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.green, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(1, 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      final client = ApiClient();
      sl.registerSingleton<ApiClient>(client);
      final requested = <int>[];
      final pending = <Completer<void>>[];
      client.dio.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) async {
        expect(request.path,
            contains('/${type == 'wake' ? 'morning' : 'night'}/'));
        final id = int.parse(request.path.split('/').last);
        requested.add(id);
        if (![100, 1, 2, 3].contains(id)) {
          final gate = Completer<void>();
          pending.add(gate);
          await gate.future;
        }
        handler
            .resolve(Response<List<int>>(requestOptions: request, data: bytes));
      }));
      await tester.pumpWidget(MaterialApp(
          home: RoutinePoster(event: {
        'eventType': type,
        'occurredAt': '2026-04-10T00:00:00Z',
        'quote': '原始文案',
        'source': 'live',
      })));
      for (var step = 0; step < 8; step++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
      expect(requested, [100, 1, 2, 3]);
      final change = find.widgetWithText(OutlinedButton, '换一张');
      await tester.scrollUntilVisible(change, 150);
      final watch = Stopwatch()..start();
      for (var index = 0; index < 3; index++) {
        await tester.tap(change);
        await tester.pumpAndSettle();
        expect(tester.widget<OutlinedButton>(change).onPressed, isNotNull);
        expect(find.text('正在加载新图片…'), findsNothing);
      }
      watch.stop();
      expect(
          requested.where((id) => [100, 1, 2, 3].contains(id)), [100, 1, 2, 3]);
      expect(pending, hasLength(3));
      debugPrint(
          '$type: three prepared switches ${watch.elapsedMilliseconds} ms; next requests still pending');
      await tester.pumpWidget(const SizedBox());
      for (final gate in pending) {
        gate.complete();
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      expect(tester.takeException(), isNull);
    });
  }

  for (final period in ['wake', 'bed']) {
    testWidgets('$period never displays legacy themes without login',
        (tester) async {
      final event = {
        'eventType': period,
        'occurredAt': '2026-10-20T00:00:00Z',
        'quote': '规律地照顾自己',
        'source': 'live',
      };
      final original = Map.of(event);
      await tester.pumpWidget(MaterialApp(home: RoutinePoster(event: event)));
      final previousQuote = event['quote']!;
      final change = find.widgetWithText(OutlinedButton, '换一张');
      await tester.scrollUntilVisible(change, 150);
      for (var i = 0; i < 8; i++) {
        await tester.tap(change);
        await tester.pumpAndSettle();
        expect(
            tester
                .widgetList<Image>(find.byType(Image))
                .map((image) => image.image)
                .whereType<AssetImage>()
                .where((image) => image.assetName.contains('routine-')),
            isEmpty);
        expect(find.text(previousQuote), findsOneWidget);
        expect(event, original);
        expect(tester.takeException(), isNull);
      }
    });
  }

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
