import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:health_reset_plan/core/payment/payment_api.dart';
import 'package:health_reset_plan/core/payment/payment_service.dart';
import 'package:health_reset_plan/features/payment/ai_credit_page.dart';

void main() {
  final getIt = GetIt.instance;

  tearDown(() async => getIt.reset());

  testWidgets('会员中心在手机大字体下完整显示', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.reset);

    final client = ApiClient(adapter: _MembershipAdapter());
    getIt.registerSingleton<PaymentService>(
      PaymentService(api: PaymentApi(client: client)),
    );

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: const AiCreditPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('14 天成长体验中'), findsOneWidget);
    expect(find.text('VIP 会员'), findsOneWidget);
    expect(find.text('VIP 季卡'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('额外加量'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('额外加量'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MembershipAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = switch (options.path) {
      '/ai-credits/products' => [
          _product('vip_month', 'VIP 月卡', 690, 30, 'vip'),
          _product('vip_quarter', 'VIP 季卡', 1800, 90, 'vip'),
          _product('vip_year', 'VIP 年卡', 5900, 360, 'vip'),
          _product('ai_10_trial', '新人体验包', 190, 10, 'credit'),
          _product('ai_30', 'AI 健康分析包', 990, 30, 'credit'),
          _product('ai_80', 'AI 健康分析大容量包', 1990, 80, 'credit'),
        ],
      '/ai-credits/balance' => {
          'balance': 8,
          'gifted_total': 3,
          'purchased_total': 10,
          'consumed_total': 5,
          'channels': {'wechat': true, 'alipay': true},
        },
      '/ai-credits/vip-status' => {'active': false},
      '/ai-credits/entitlements' => {
          'tier': 'trial',
          'trialActive': true,
          'trialExpiresAt': '2026-09-09T12:00:00',
          'creditBalance': 8,
          'benefits': const [],
        },
      '/ai-credits/ledger' || '/ai-credits/orders' => const [],
      _ => const {},
    };
    return ResponseBody.fromString(
      jsonEncode({'code': 0, 'msg': '成功', 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  static Map<String, Object> _product(
    String code,
    String name,
    int price,
    int credits,
    String kind,
  ) =>
      {
        'code': code,
        'name': name,
        'price_fen': price,
        'credit_amount': credits,
        'kind': kind,
      };

  @override
  void close({bool force = false}) {}
}
