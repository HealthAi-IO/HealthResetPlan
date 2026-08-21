import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:get_it/get_it.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_response.dart';
import '../../core/payment/payment_service.dart';
import '../../core/widgets/motion.dart';
import 'ai_credit_view_data.dart';

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
  List<Map<String, dynamic>> _products = visibleAiCreditProducts(
    _defaultProducts,
    isDevelopment: appFlavor == 'development',
    isInternal: appReleaseChannel == 'internal',
  );
  Map<String, dynamic> _balance = const {};
  ({int gifted, int purchased}) _sources = (gifted: 0, purchased: 0);
  String? _selectedProductCode = 'ai_60';
  String _channel = 'wechat';
  bool _paying = false;
  bool _balanceAvailable = false;
  List<Map<String, dynamic>> _orders = const [];

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
    final ledgerFuture =
        _service.ledger().catchError((_) => <Map<String, dynamic>>[]);
    final ordersFuture =
        _service.orders().catchError((_) => <Map<String, dynamic>>[]);
    final products = await productsFuture;
    final balanceResult = await balanceFuture;
    final ledger = await ledgerFuture;
    final orders = await ordersFuture;
    final balance = balanceResult.balance;
    final balanceAvailable = balanceResult.available;
    final ledgerSources = aiCreditSources(ledger);
    if (!mounted) return;

    final currentSelectionExists = products.any(
      (product) => '${product['code']}' == _selectedProductCode,
    );
    final recommended = products.isEmpty
        ? null
        : products.reduce(
            (current, next) => _intValue(next['credit_amount']) >
                    _intValue(current['credit_amount'])
                ? next
                : current,
          );
    setState(() {
      _products = products;
      _balance = balance;
      _sources = (
        gifted: balance.containsKey('gifted_total')
            ? creditIntValue(balance['gifted_total'])
            : ledgerSources.gifted,
        purchased: balance.containsKey('purchased_total')
            ? creditIntValue(balance['purchased_total'])
            : ledgerSources.purchased,
      );
      _balanceAvailable = balanceAvailable;
      _orders = orders;
      if (!currentSelectionExists && recommended != null) {
        _selectedProductCode = '${recommended['code']}';
      }
    });
  }

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    try {
      final products = await _service.products().timeout(
            const Duration(seconds: 5),
          );
      return visibleAiCreditProducts(
        products.isEmpty ? _defaultProducts : products,
        isDevelopment: appFlavor == 'development',
        isInternal: appReleaseChannel == 'internal',
      );
    } catch (_) {
      return visibleAiCreditProducts(
        _defaultProducts,
        isDevelopment: appFlavor == 'development',
        isInternal: appReleaseChannel == 'internal',
      );
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

  Future<void> _showOrders() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: _OrderList(
            orders: _orders,
            onRefund: (order) async {
              Navigator.pop(sheetContext);
              await _requestRefund(order);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _requestRefund(Map<String, dynamic> order) async {
    final orderNo = '${order['order_no'] ?? order['orderNo'] ?? ''}';
    if (orderNo.isEmpty) {
      _message('订单信息不完整，请刷新后重试');
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RefundReasonDialog(),
    );
    if (reason == null || !mounted) return;
    try {
      final result = await _service.requestRefund(orderNo, reason: reason);
      if (mounted) {
        _message(_refundResultMessage(result['status']));
      }
      await _load();
    } catch (error) {
      if (mounted) _message(_refundErrorMessage(error));
    }
  }

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
              gifted: _sources.gifted,
              purchased: _sources.purchased,
            ),
            const SizedBox(height: 26),
            Text('选择次数包', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '所有次数包均可用于全部 AI 健康权益',
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
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _orders.isEmpty ? null : _showOrders,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('订单与退款'),
            ),
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

class _RefundReasonDialog extends StatefulWidget {
  const _RefundReasonDialog();

  @override
  State<_RefundReasonDialog> createState() => _RefundReasonDialogState();
}

class _RefundReasonDialogState extends State<_RefundReasonDialog> {
  static const _reasons = [
    '误操作购买',
    '重复购买',
    '暂时不需要 AI 次数',
    '支付金额或方式有疑问',
    '其他原因',
  ];

  final _otherReasonController = TextEditingController();
  String _selectedReason = _reasons.first;

  bool get _isOther => _selectedReason == _reasons.last;
  String get _reason =>
      _isOther ? _otherReasonController.text.trim() : _selectedReason;
  bool get _canSubmit => !_isOther || _reason.length >= 2;

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('选择退款原因'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '仅支持支付后 7 天内且本订单次数完全未使用。审核通过后原路退回。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final reason in _reasons)
              Semantics(
                selected: reason == _selectedReason,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  minVerticalPadding: 0,
                  leading: Icon(
                    reason == _selectedReason
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: reason == _selectedReason
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  title: Text(reason),
                  onTap: () => setState(() => _selectedReason = reason),
                ),
              ),
            if (_isOther) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _otherReasonController,
                autofocus: true,
                minLines: 2,
                maxLines: 3,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '填写其他原因',
                  hintText: '请输入至少 2 个字符',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _canSubmit ? () => Navigator.pop(context, _reason) : null,
          child: const Text('提交申请'),
        ),
      ],
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders, required this.onRefund});

  final List<Map<String, dynamic>> orders;
  final Future<void> Function(Map<String, dynamic>) onRefund;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('订单与退款', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('已支付且次数完全未使用的订单，可在支付后 7 天内申请退款。'),
        const SizedBox(height: 16),
        if (orders.isEmpty) const Text('暂无订单'),
        for (final order in orders) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
                '${order['product_name'] ?? 'AI 次数包'} · ${_priceText(order['amount_fen'])}'),
            subtitle: Text(_orderDescription(order)),
            trailing: _canRefund(order)
                ? TextButton(
                    onPressed: () => onRefund(order), child: const Text('退款'))
                : null,
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

bool _canRefund(Map<String, dynamic> order) =>
    order['status'] == 'paid' &&
    _intValue(order['remaining_credit']) == _intValue(order['credit_amount']);

String _orderDescription(Map<String, dynamic> order) {
  final refundStatus = '${order['refund_status'] ?? ''}';
  final orderStatus = '${order['status'] ?? ''}';
  final status = switch (refundStatus) {
    'submitting' => '正在提交退款',
    'processing' => '退款处理中',
    'completed' => '退款成功',
    'needs_manual' => '需要人工处理',
    'rejected' => '退款未通过',
    _ => switch (orderStatus) {
        'paid' => '已支付',
        'refunded' => '已退款',
        'refund_processing' => '退款处理中',
        'refund_rejected' => '退款未通过',
        'expired' => '已过期',
        'failed' => '失败',
        _ => '处理中',
      },
  };
  final failureReason = '${order['refund_failure_reason'] ?? ''}'.trim();
  final summary = '状态：$status · 剩余 ${_intValue(order['remaining_credit'])} 次';
  return failureReason.isEmpty ? summary : '$summary\n$failureReason';
}

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary({
    required this.balance,
    required this.available,
    required this.gifted,
    required this.purchased,
  });

  final Map<String, dynamic> balance;
  final bool available;
  final int gifted;
  final int purchased;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child:
                    Icon(Icons.auto_awesome_rounded, color: colors.onPrimary),
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
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      available ? '成功生成扣 1 次，失败不扣次' : '购买后次数永久有效，不自动续费',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (available) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Text('累计赠送 $gifted 次')),
                Expanded(child: Text('累计购买 $purchased 次')),
                Expanded(
                    child:
                        Text('已使用 ${_intValue(balance['consumed_total'])} 次')),
              ],
            ),
          ],
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
                      Text(
                        '$credits 次 AI 健康分析',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (recommended || '${product['code']}' == 'ai_test_1')
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: _ProductBadge(
                            label: recommended ? '更划算' : '仅测试版',
                            color: recommended
                                ? colors.secondaryContainer
                                : colors.tertiaryContainer,
                          ),
                        ),
                      const SizedBox(height: 4),
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

class _ProductBadge extends StatelessWidget {
  const _ProductBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
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

String _refundErrorMessage(Object error) {
  if (error is DioException && error.error is ApiResponseException) {
    return (error.error as ApiResponseException).message;
  }
  return '退款申请失败，请检查网络后重试';
}

String _refundResultMessage(Object? status) => switch ('$status') {
      'completed' => '退款成功，款项将按支付渠道原路退回',
      'processing' => '退款已受理，正在等待支付渠道处理',
      'needs_manual' => '渠道结果暂不确定，已转入异常处理，不会重复退款',
      _ => '退款申请已提交',
    };
