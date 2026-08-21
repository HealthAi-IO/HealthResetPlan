import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/features/payment/ai_credit_view_data.dart';

void main() {
  test('test payment product is visible only in development or internal builds',
      () {
    final products = <Map<String, dynamic>>[
      {'code': 'ai_test_1'},
      {'code': 'ai_20'},
    ];

    expect(
      visibleAiCreditProducts(
        products,
        isDevelopment: true,
        isInternal: false,
      ),
      hasLength(2),
    );
    expect(
      visibleAiCreditProducts(
        products,
        isDevelopment: false,
        isInternal: true,
      ),
      hasLength(2),
    );
    expect(
      visibleAiCreditProducts(
        products,
        isDevelopment: false,
        isInternal: false,
      ).map((product) => product['code']),
      ['ai_20'],
    );
  });

  test('credit sources distinguish grants and purchases', () {
    final sources = aiCreditSources([
      {'reason': 'trial', 'change_amount': 3},
      {'reason': 'purchase', 'change_amount': 20},
      {'reason': 'consume', 'change_amount': -1},
      {'reason': 'refund', 'change_amount': -20},
    ]);

    expect(sources.gifted, 3);
    expect(sources.purchased, 20);
  });
}
