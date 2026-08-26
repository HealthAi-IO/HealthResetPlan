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
      'code': 'ai_10_trial',
      'name': '新人体验包',
      'price_fen': 190,
      'credit_amount': 10,
      'kind': 'credit',
      'badge': '首购',
      'subtitle': '先低价试用，觉得有用再继续买',
    },
    {
      'code': 'ai_30',
      'name': 'AI 健康分析包',
      'price_fen': 990,
      'credit_amount': 30,
      'kind': 'credit',
      'badge': '推荐',
      'subtitle': '适合偶尔使用，单次成本更低',
    },
    {
      'code': 'ai_80',
      'name': 'AI 健康分析大容量包',
      'price_fen': 1990,
      'credit_amount': 80,
      'kind': 'credit',
      'badge': '更省',
      'subtitle': '适合高频使用，单次更划算',
    },
    {
      'code': 'vip_month',
      'name': 'VIP 月卡',
      'price_fen': 690,
      'kind': 'vip',
      'badge': '体验',
      'subtitle': '每月固定权益，次月手动续费',
    },
    {
      'code': 'vip_quarter',
      'name': 'VIP 季卡',
      'price_fen': 1800,
      'kind': 'vip',
      'badge': '省心',
      'subtitle': '90 天有效，手动续费',
    },
    {
      'code': 'vip_year',
      'name': 'VIP 年卡',
      'price_fen': 5900,
      'kind': 'vip',
      'badge': '长期',
      'subtitle': '长期管理更省心',
    },
  ];

  final _service = GetIt.instance<PaymentService>();
  List<Map<String, dynamic>> _products = visibleAiCreditProducts(
    _defaultProducts,
    isDevelopment: appFlavor == 'development',
    isInternal: appReleaseChannel == 'internal',
  );
  Map<String, dynamic> _balance = const {};
  Map<String, dynamic> _vipStatus = const {};
  Map<String, dynamic> _entitlements = const {};
  ({int gifted, int purchased}) _sources = (gifted: 0, purchased: 0);
  String? _selectedProductCode = 'vip_quarter';
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
    final vipStatusFuture =
        _service.vipStatus().catchError((_) => <String, dynamic>{});
    final entitlementsFuture =
        _service.entitlements().catchError((_) => <String, dynamic>{});
    final ledgerFuture =
        _service.ledger().catchError((_) => <Map<String, dynamic>>[]);
    final ordersFuture =
        _service.orders().catchError((_) => <Map<String, dynamic>>[]);
    final products = await productsFuture;
    final balanceResult = await balanceFuture;
    final vipStatus = await vipStatusFuture;
    final entitlements = await entitlementsFuture;
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
      _vipStatus = vipStatus;
      _entitlements = entitlements;
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
      return _mergeProducts(
        visibleAiCreditProducts(
          products,
          isDevelopment: appFlavor == 'development',
          isInternal: appReleaseChannel == 'internal',
        ),
      );
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
        result['status'] == 'paid'
            ? '${product['kind']}' == 'vip'
                ? '支付成功，VIP 已开通'
                : '支付成功，次数已到账'
            : '订单处理中，请稍后刷新',
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
      appBar: AppBar(title: const Text('AI 权益购买')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _EntitlementSummary(
              entitlements: _entitlements,
              vipStatus: _vipStatus,
            ),
            const SizedBox(height: 26),
            Text('VIP 会员', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '把每天的记录变成持续、完整的健康管理',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const _VipBenefitList(),
            const SizedBox(height: 14),
            ..._vipProducts.map(
              (product) => MotionFadeSlide(
                delay:
                    Duration(milliseconds: _vipProducts.indexOf(product) * 45),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ProductOption(
                    product: product,
                    selected: '${product['code']}' == _selectedProductCode,
                    recommended: '${product['code']}' == 'vip_quarter',
                    onTap: () => setState(
                      () => _selectedProductCode = '${product['code']}',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title:
                  Text('额外加量', style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(
                '偶尔使用，或周期权益用完后再购买',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              children: [
                _BalanceSummary(
                  balance: _balance,
                  available: _balanceAvailable,
                  gifted: _sources.gifted,
                  purchased: _sources.purchased,
                ),
                const SizedBox(height: 12),
                ..._creditProducts.map(
                  (product) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ProductOption(
                      product: product,
                      selected: '${product['code']}' == _selectedProductCode,
                      recommended: '${product['code']}' == 'ai_80',
                      onTap: () => setState(
                        () => _selectedProductCode = '${product['code']}',
                      ),
                    ),
                  ),
                ),
              ],
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
                            _selectedProductLabel(selectedProduct),
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

  List<Map<String, dynamic>> get _creditProducts => _products
      .where((product) => '${product['kind']}' == 'credit')
      .toList(growable: false);

  List<Map<String, dynamic>> get _vipProducts => _products
      .where((product) => '${product['kind']}' == 'vip')
      .toList(growable: false);

  List<Map<String, dynamic>> _mergeProducts(
    List<Map<String, dynamic>> products,
  ) {
    final byCode = <String, Map<String, dynamic>>{
      for (final product in products) '${product['code']}': product,
    };
    return _defaultProducts.map((defaultProduct) {
      final merged = <String, dynamic>{...defaultProduct};
      final apiProduct = byCode['${defaultProduct['code']}'];
      if (apiProduct != null) merged.addAll(apiProduct);
      return merged;
    }).toList(growable: false);
  }

  String _selectedProductLabel(Map<String, dynamic>? product) {
    if (product == null) return '';
    return switch ('${product['code']}') {
      'vip_month' => 'VIP 月卡',
      'vip_quarter' => 'VIP 季卡',
      'vip_year' => 'VIP 年卡',
      _ => '${_intValue(product['credit_amount'])} 次',
    };
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
    _intValue(order['benefit_used']) == 0 &&
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

class _EntitlementSummary extends StatelessWidget {
  const _EntitlementSummary({
    required this.entitlements,
    required this.vipStatus,
  });

  final Map<String, dynamic> entitlements;
  final Map<String, dynamic> vipStatus;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tier = '${entitlements['tier'] ?? 'free'}';
    final isVip = tier == 'vip' || vipStatus['active'] == true;
    final isTrial = tier == 'trial';
    final title = isVip
        ? 'VIP 健康管理中'
        : isTrial
            ? '14 天成长体验中'
            : '免费健康管理';
    final detail = isVip
        ? _expiryText(vipStatus['expires_at'], prefix: '有效期至')
        : isTrial
            ? _expiryText(entitlements['trialExpiresAt'], prefix: '体验至')
            : '三餐识别、每日管家和基础周报可持续使用';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            isVip
                ? Icons.workspace_premium_rounded
                : isTrial
                    ? Icons.auto_awesome_rounded
                    : Icons.favorite_outline_rounded,
            size: 32,
            color: colors.onPrimaryContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
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

  String _expiryText(Object? raw, {required String prefix}) {
    final date = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    if (date == null) return '权益状态加载中';
    return '$prefix ${date.year}年${date.month}月${date.day}日';
  }
}

class _VipBenefitList extends StatelessWidget {
  const _VipBenefitList();

  static const _benefits = [
    '健康管家每天最多 10 个会话，每个会话含 10 轮交流',
    '三餐识别与 AI 换餐每天各 3 次',
    '个性化菜单、运动计划和健康周报每周各 1 次',
    '体检报告每月 3 次，健康自检合计每月 6 次',
    '每日健康摘要与 30 天趋势分析',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: _benefits
            .map(
              (benefit) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 20, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(benefit)),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
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
                      available ? '健康管家按会话计费，其他能力成功后扣次' : '购买后次数永久有效，不自动续费',
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
    final kind = '${product['kind']}';
    final title =
        kind == 'vip' ? '${product['name']}' : '$credits 次 ${product['name']}';
    final subtitle = '${product['subtitle'] ?? ''}';
    final badge = '${product['badge'] ?? ''}';
    return Semantics(
      button: true,
      selected: selected,
      label: '$title，${_priceText(product['price_fen'])}',
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
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      if (recommended || badge.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: _ProductBadge(
                            label: recommended ? '更划算' : badge,
                            color: recommended
                                ? colors.secondaryContainer
                                : colors.tertiaryContainer,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
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
          '健康记录功能永久免费。AI 次数包适合偶尔使用，VIP 月卡和年卡适合持续追踪。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Text(
          '月卡和年卡均为手动续费，不会自动扣款。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Text(
          '支付后 7 天内且所购次数或 VIP 权益完全未使用，可申请退款，审核通过后由原支付渠道退回。',
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
  if (error is DioException) {
    if (error.error is ApiResponseException) {
      return (error.error as ApiResponseException).message;
    }
    final body = error.response?.data;
    if (body is Map) {
      final message = '${body['msg'] ?? body['message'] ?? ''}'.trim();
      if (message.isNotEmpty) return message;
    }
  }
  return '退款申请失败，请检查网络后重试';
}

String _refundResultMessage(Object? status) => switch ('$status') {
      'completed' => '退款成功，款项将按支付渠道原路退回',
      'processing' => '退款已受理，正在等待支付渠道处理',
      'needs_manual' => '渠道结果暂不确定，已转入异常处理，不会重复退款',
      _ => '退款申请已提交',
    };
