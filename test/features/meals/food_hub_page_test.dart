import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_repository.dart';
import 'package:health_reset_plan/core/di/service_locator.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:health_reset_plan/core/network/online_data_api.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';
import 'package:health_reset_plan/features/meals/food_hub_page.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  final database = AppDatabase.instance;
  final repository = HealthRepository(database: database);

  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
    await database.open();
    await database.switchSpace('food-hub-widget-test');
    await database.bindOnline(
      OnlineDataApi(client: ApiClient(adapter: _EmptyDataAdapter())),
    );
    await repository.initialize();
    await repository.ensureStarterMealRecipes();
    sl.registerSingleton<HealthRepository>(repository);
  });

  tearDownAll(() async {
    await sl.reset();
  });

  testWidgets('菜谱页在较大系统字体下可正常显示', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(
      () => repository.addPlan(
        date: DateTime.now(),
        type: 'meal',
        payload: const {
          'breakfast': ['测试早餐'],
        },
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(body: FoodHubPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('菜谱'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('定制专属 7 天菜单'), findsOneWidget);
    expect(find.text('番茄鸡蛋杂粮饭'), findsOneWidget);

    await tester.tap(find.text('本周定制菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('菜谱'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('本周定制菜单'), findsOneWidget);
  });

  testWidgets('饮食预算使用数字键盘输入并显示日均金额', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FoodHubPage())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('饮食预算'));
    await tester.pumpAndSettle();

    final switchFinder = find.byType(Switch);
    if (!tester.widget<Switch>(switchFinder).value) {
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
    }

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).keyboardType,
      TextInputType.number,
    );

    await tester.enterText(find.byType(TextField), '2000');
    await tester.pump();
    expect(find.text('约每天 66.7 元'), findsOneWidget);
  });
}

class _EmptyDataAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.method == 'GET'
        ? {'version': 0, 'data': <String, dynamic>{}}
        : {'version': 1, 'data': <String, dynamic>{}};
    return ResponseBody.fromString(
      jsonEncode({'code': 0, 'msg': '成功', 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
