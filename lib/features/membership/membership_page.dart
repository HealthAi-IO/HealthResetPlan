import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/membership_service.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  final MembershipService _service = sl<MembershipService>();

  MembershipStatus _status = MembershipStatus.free;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await _service.getStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _showActivationDialog({
    required String planCode,
    required String planName,
    required int days,
    required String priceLabel,
  }) async {
    final codeCtrl = TextEditingController();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('开通$planName'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BenefitRow(icon: Icons.cloud_sync_outlined, text: '加密云同步，多端数据安全备份'),
                const SizedBox(height: 8),
                _BenefitRow(icon: Icons.document_scanner_outlined, text: '体检报告 OCR 智能识别'),
                const SizedBox(height: 8),
                _BenefitRow(icon: Icons.psychology_outlined, text: 'AI 健康方案无限次生成'),
                if (planCode == 'yearly') ...[
                  const SizedBox(height: 8),
                  _BenefitRow(icon: Icons.support_agent_outlined, text: '年度专属优先客服响应'),
                ],
                const SizedBox(height: 20),
                Text('价格：$priceLabel',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppTheme.deepBlue)),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                const Text('已有激活码？',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: '输入激活码（如 HEALTH30）',
                    errorText: errorText,
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                  ),
                  onChanged: (_) {
                    if (errorText != null) setS(() => errorText = null);
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final code = codeCtrl.text.trim();
                      if (code.isEmpty) {
                        setS(() => errorText = '请输入激活码');
                        return;
                      }
                      final navigator = Navigator.of(ctx);
                      final ok = await _service.activateWithCode(code);
                      if (ok) {
                        navigator.pop(true);
                      } else {
                        setS(() => errorText = '激活码无效或已使用');
                      }
                    },
                    child: const Text('兑换激活码'),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.pageBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('在线支付开通（即将上线）',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      SizedBox(height: 4),
                      Text(
                        '支付宝 / 微信支付 / Apple Pay 即将开放。\n'
                        '现阶段可联系客服获取激活码开通会员。',
                        style: TextStyle(
                            color: AppTheme.muted, fontSize: 12, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );

    codeCtrl.dispose();
    if (confirmed == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会员已开通，享受所有权益！')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会员中心')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _StatusCard(status: _status),
                const SizedBox(height: 20),
                const Text('选择套餐',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (_, c) {
                  final wide = c.maxWidth >= 600;
                  final monthly = _PlanCard(
                    title: '月度会员',
                    price: '¥18',
                    unit: '/ 月',
                    subPrice: '',
                    isRecommended: false,
                    features: const [
                      '加密云同步',
                      '体检报告 OCR',
                      'AI 方案无限次',
                    ],
                    onTap: () => _showActivationDialog(
                      planCode: 'monthly',
                      planName: '月度会员',
                      days: 31,
                      priceLabel: '¥18 / 月',
                    ),
                  );
                  final yearly = _PlanCard(
                    title: '年度会员',
                    price: '¥98',
                    unit: '/ 年',
                    subPrice: '≈ ¥8.2 / 月，省 ¥118',
                    isRecommended: true,
                    features: const [
                      '加密云同步',
                      '体检报告 OCR',
                      'AI 方案无限次',
                      '年度专属客服',
                    ],
                    onTap: () => _showActivationDialog(
                      planCode: 'yearly',
                      planName: '年度会员',
                      days: 366,
                      priceLabel: '¥98 / 年',
                    ),
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: monthly),
                        const SizedBox(width: 12),
                        Expanded(child: yearly),
                      ],
                    );
                  }
                  return Column(children: [
                    yearly,
                    const SizedBox(height: 12),
                    monthly,
                  ]);
                }),
                const SizedBox(height: 20),
                _BenefitsPanel(),
                const SizedBox(height: 20),
                _PromoCodeEntry(
                  onActivate: (code) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await _service.activateWithCode(code);
                    if (!mounted) return;
                    if (ok) {
                      await _load();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('激活成功，会员权益已开通！')),
                      );
                    } else {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('激活码无效或已使用'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
    );
  }
}

// ── 状态卡片 ──────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final MembershipStatus status;

  @override
  Widget build(BuildContext context) {
    if (status.isActive) {
      final expiry = DateFormat('yyyy/MM/dd').format(status.expiresAt!);
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0277BD), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.workspace_premium, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(status.planName ?? '会员版',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('已激活',
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ]),
              const SizedBox(height: 4),
              Text('有效期至 $expiry',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.pageBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.person_outline, color: AppTheme.muted, size: 26),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('免费版',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text('升级会员解锁云同步、AI无限次等高级权益',
                style: TextStyle(color: AppTheme.muted, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

// ── 套餐卡片 ──────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.unit,
    required this.subPrice,
    required this.isRecommended,
    required this.features,
    required this.onTap,
  });

  final String title;
  final String price;
  final String unit;
  final String subPrice;
  final bool isRecommended;
  final List<String> features;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isRecommended ? AppTheme.deepBlue : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRecommended ? AppTheme.deepBlue : AppTheme.cardBorder,
          width: isRecommended ? 0 : 1,
        ),
        boxShadow: isRecommended
            ? [
                BoxShadow(
                    color: AppTheme.deepBlue.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4))
              ]
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isRecommended ? Colors.white : AppTheme.ink)),
          if (isRecommended) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('推荐',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(price,
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: isRecommended ? Colors.white : AppTheme.deepBlue)),
          const SizedBox(width: 2),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(unit,
                style: TextStyle(
                    fontSize: 14,
                    color: isRecommended ? Colors.white70 : AppTheme.muted)),
          ),
        ]),
        if (subPrice.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subPrice,
              style: TextStyle(
                  fontSize: 12,
                  color: isRecommended ? Colors.white70 : AppTheme.muted)),
        ],
        const SizedBox(height: 14),
        for (final f in features) ...[
          Row(children: [
            Icon(Icons.check_circle_outline,
                size: 15,
                color: isRecommended ? Colors.white70 : AppTheme.deepBlue),
            const SizedBox(width: 6),
            Text(f,
                style: TextStyle(
                    fontSize: 13,
                    color: isRecommended ? Colors.white : AppTheme.ink)),
          ]),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: isRecommended ? Colors.white : AppTheme.deepBlue,
              foregroundColor: isRecommended ? AppTheme.deepBlue : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text('开通$title',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

// ── 权益对比面板 ──────────────────────────────────────────────

class _BenefitsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('会员权益详情',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(1.5),
            2: FlexColumnWidth(1.5),
          },
          children: [
            _tableHeader(),
            _tableRow('加密云同步', true, true),
            _tableRow('体检报告 OCR', true, true),
            _tableRow('AI 方案无限次', true, true),
            _tableRow('优先客服响应', false, true),
          ],
        ),
      ]),
    );
  }

  TableRow _tableHeader() {
    TextStyle headerStyle(Color c) =>
        TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c);
    return TableRow(children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text('权益项目',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.muted)),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(child: Text('月度', style: headerStyle(AppTheme.muted))),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
            child: Text('年度', style: headerStyle(AppTheme.deepBlue))),
      ),
    ]);
  }

  TableRow _tableRow(String name, bool monthly, bool yearly) {
    Widget mark(bool v) => Center(
          child: Icon(
            v ? Icons.check_circle : Icons.remove,
            size: 18,
            color: v ? AppTheme.deepBlue : AppTheme.muted,
          ),
        );
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(name, style: const TextStyle(fontSize: 13)),
      ),
      mark(monthly),
      mark(yearly),
    ]);
  }
}

// ── 激活码兑换区 ──────────────────────────────────────────────

class _PromoCodeEntry extends StatefulWidget {
  const _PromoCodeEntry({required this.onActivate});
  final Future<void> Function(String code) onActivate;

  @override
  State<_PromoCodeEntry> createState() => _PromoCodeEntryState();
}

class _PromoCodeEntryState extends State<_PromoCodeEntry> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    await widget.onActivate(code);
    if (mounted) {
      _ctrl.clear();
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.vpn_key_outlined, size: 18, color: AppTheme.deepBlue),
          SizedBox(width: 8),
          Text('激活码兑换',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        const Text('输入激活码立即开通对应会员权益',
            style: TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: '请输入激活码',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('兑换'),
          ),
        ]),
      ]),
    );
  }
}

// ── 权益行 ────────────────────────────────────────────────────

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: AppTheme.deepBlue),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontSize: 13)),
    ]);
  }
}
