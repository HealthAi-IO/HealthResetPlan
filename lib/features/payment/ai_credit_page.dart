import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/payment/payment_service.dart';
import '../../core/widgets/motion.dart';

class AiCreditPage extends StatefulWidget {
  const AiCreditPage({super.key});

  @override
  State<AiCreditPage> createState() => _AiCreditPageState();
}

class _AiCreditPageState extends State<AiCreditPage> {
  static const _defaultProducts = [
    {
      'code': 'ai_test_1',
      'name': '支付测试包',
      'price_fen': 1,
      'credit_amount': 1,
    },
    {
      'code': 'ai_20',
      'name': 'AI 健康分析包',
      'price_fen': 990,
      'credit_amount': 20,
    },
    {
      'code': 'ai_60',
      'name': 'AI 健康分析大容量包',
      'price_fen': 1990,
      'credit_amount': 60,
    },
  ];

  final _service = GetIt.instance<PaymentService>();
  List<Map<String, dynamic>> _products = _defaultProducts;
  Map<String, dynamic> _balance = const {};
  String? _selectedProductCode = 'ai_60';
  String _channel = 'wechat';
  bool _paying = false;
  bool _balanceAvailable = false;

  Map<String, dynamic>? get _selectedProduct {
    for (final product in _products) {
      if ('${product['code']}' == _selectedProductCode) return product;
    }
    return null;
  }

  String get _channelName => _channel == 'wechat' ? '微信' : '支付宝';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final productsFuture = _loadProducts();
    final balanceFuture = _loadBalance();
    final products = await productsFuture;
    final balanceResult = await balanceFuture;
    final balance = balanceResult.balance;
    final balanceAvailable = balanceResult.available;
    if (!mounted) return;

    final currentSelectionExists = products.any(
      (product) => '${product['code']}' == _selectedProductCode,
    );
    final recommended = products.reduce(
      (current, next) =>
          _intValue(next['credit_amount']) > _intValue(current['credit_amount'])
              ? next
              : current,
    );
    setState(() {
      _products = products;
      _balance = balance;
      _balanceAvailable = balanceAvailable;
      if (!currentSelectionExists) {
        _selectedProductCode = '${recommended['code']}';
      }
    });
  }

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    try {
      final products = await _service.products().timeout(
            const Duration(seconds: 5),
          );
      return products.isEmpty ? _defaultProducts : products;
    } catch (_) {
      return _defaultProducts;
    }
  }

  Future<({Map<String, dynamic> balance, bool available})>
      _loadBalance() async {
    try {
      final balance = await _service.balance().timeout(
            const Duration(seconds: 5),
          );
      return (balance: balance, available: true);
    } catch (_) {
      return (balance: const <String, dynamic>{}, available: false);
    }
  }

  Future<void> _buy() async {
    final product = _selectedProduct;
    if (product == null || _paying) return;
    setState(() => _paying = true);
    try {
      final result = await _service.purchase(
        productCode: '${product['code']}',
        channel: _channel,
      );
      if (!mounted) return;
      _message(
        result['status'] == 'paid' ? '支付成功，次数已到账' : '订单处理中，请稍后刷新',
      );
      await _load();
    } catch (_) {
      if (mounted) _message('$_channelName支付暂不可用，请稍后重试');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final selectedProduct = _selectedProduct;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 次数包')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _BalanceSummary(
              balance: _balance,
              available: _balanceAvailable,
            ),
            const SizedBox(height: 26),
            Text('选择次数包', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '两种次数包均可用于全部 AI 健康权益',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ..._products.map(
              (product) => MotionFadeSlide(
                delay: Duration(milliseconds: _products.indexOf(product) * 45),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ProductOption(
                    product: product,
                    selected: '${product['code']}' == _selectedProductCode,
                    recommended: _intValue(product['credit_amount']) ==
                        _products
                            .map((item) => _intValue(item['credit_amount']))
                            .reduce((a, b) => a > b ? a : b),
                    onTap: () => setState(
                      () => _selectedProductCode = '${product['code']}',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('支付方式', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'wechat',
                    label: Text('微信支付'),
                    icon: Icon(Icons.chat_bubble_outline_rounded),
                  ),
                  ButtonSegment(
                    value: 'alipay',
                    label: Text('支付宝'),
                    icon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                ],
                selected: {_channel},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _channel = value.first),
              ),
            ),
            const SizedBox(height: 22),
            const _PurchaseNotice(),
          ],
        ),
      ),
      bottomNavigationBar: selectedProduct == null
          ? null
          : Material(
              elevation: 10,
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_intValue(selectedProduct['credit_amount'])} 次',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            _priceText(selectedProduct['price_fen']),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _paying ? null : _buy,
                      icon: _paying
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _channel == 'wechat'
                                  ? Icons.chat_bubble_outline_rounded
                                  : Icons.account_balance_wallet_outlined,
                            ),
                      label: Text(_paying ? '正在支付' : '$_channelName支付'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary({required this.balance, required this.available});

  final Map<String, dynamic> balance;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: colors.onPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  available
                      ? '剩余 ${_intValue(balance['balance'])} 次'
                      : 'AI 健康权益',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  available ? '次数永久有效，不自动续费' : '购买后次数永久有效，不自动续费',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductOption extends StatelessWidget {
  const _ProductOption({
    required this.product,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  final Map<String, dynamic> product;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final credits = _intValue(product['credit_amount']);
    return Semantics(
      button: true,
      selected: selected,
      label: '$credits 次，${_priceText(product['price_fen'])}',
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$credits 次 AI 健康分析',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (recommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: colors.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '更划算',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: colors.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '永久有效 · 全部 AI 权益通用',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _priceText(product['price_fen']),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PurchaseNotice extends StatelessWidget {
  const _PurchaseNotice();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('购买说明', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '健康记录功能永久免费。AI 次数购买后立即到账，可重复购买，不自动续费。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Text(
          '支付后 7 天内且订单次数完全未使用，可联系客服申请退款，审核通过后由原支付渠道退回。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String _priceText(Object? priceFen) =>
    '¥${(_intValue(priceFen) / 100).toStringAsFixed(2)}';
