List<Map<String, dynamic>> visibleAiCreditProducts(
  List<Map<String, dynamic>> products, {
  required bool isDevelopment,
  required bool isInternal,
}) {
  return products
      .where(
        (product) =>
            isDevelopment || isInternal || '${product['code']}' != 'ai_test_1',
      )
      .toList(growable: false);
}

({int gifted, int purchased}) aiCreditSources(
  List<Map<String, dynamic>> ledger,
) {
  var gifted = 0;
  var purchased = 0;
  for (final entry in ledger) {
    final change = creditIntValue(entry['change_amount']);
    if (change <= 0) continue;
    switch ('${entry['reason']}') {
      case 'trial':
      case 'grant':
        gifted += change;
      case 'purchase':
        purchased += change;
    }
  }
  return (gifted: gifted, purchased: purchased);
}

int creditIntValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
