import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/membership_service.dart';
import '../../core/sync/sync_service.dart';

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
    // codeCtrl 由 _ActivationSheet 内部 dispose，避免外部提前释放引发 widget 错误
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true, // 关键：允许超过半屏 + 跟随键盘
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => _ActivationSheet(
        planCode: planCode,
        planName: planName,
        priceLabel: priceLabel,
        onRedeem: (code) async {
          if (code.isEmpty) return '请输入激活码';
          try {
            await _service.activateWithCode(code);
            return null;
          } on StateError catch (e) {
            return e.message;
          } catch (e) {
            return _friendly(e);
          }
        },
      ),
    );

    if (confirmed == true) {
      await _handleActivationSuccess('会员已开通，享受所有权益！');
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
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (_, c) {
                  final wide = c.maxWidth >= 600;
                  final monthly = _PlanCard(
                    title: '月度会员',
                    price: '¥2.8',
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
                      priceLabel: '¥2.8 / 月',
                    ),
                  );
                  final yearly = _PlanCard(
                    title: '年度会员',
                    price: '¥28',
                    unit: '/ 年',
                    subPrice: '≈ ¥2.3 / 月',
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
                      priceLabel: '¥28 / 年',
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
                    try {
                      await _service.activateWithCode(code);
                      await _handleActivationSuccess('激活成功，会员权益已开通！');
                    } on StateError catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(e.message),
                          backgroundColor: Colors.orange.shade700,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(_friendly(e)),
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

  Future<void> _handleActivationSuccess(String message) async {
    final shouldPromptRestoreKey = await _syncLocalData();
    if (!mounted) return;
    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );

    if (!shouldPromptRestoreKey) return;
    final restoreNow = await _showRestoreKeyDialog();
    if (!mounted) return;
    if (restoreNow == true) {
      await context.push('/sync/key-setup');
      if (!mounted) return;
      await _load();
    }
  }

  Future<bool> _syncLocalData() async {
    try {
      final sync = sl<SyncService>();
      await sync.setSyncEnabled(true);
      final umk = await sl<KeyVault>().readUmk();
      if (umk == null) return true;
      final result = await sync.sync();
      return result.hasError && _isKeyRestoreRequired(result.error);
    } catch (_) {
      // 会员激活不因同步失败中断；用户可稍后在云同步页手动重试。
      return false;
    }
  }

  bool _isKeyRestoreRequired(String? error) {
    final text = error ?? '';
    return text.contains('主密钥') ||
        text.contains('助记词') ||
        text.contains('密钥异常') ||
        text.contains('UMK');
  }

  Future<bool?> _showRestoreKeyDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要恢复云端密钥'),
        content: const Text(
          '会员权益已开通，但这台设备还没有恢复之前备份的助记词。\n\n云同步数据是端到端加密的，不恢复同一把主密钥就无法读取旧设备上传的数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('现在恢复'),
          ),
        ],
      ),
    );
  }

  String _friendly(Object e) {
    // 优先解析 DioException 的 response.data 取后端业务码和 message
    if (e is DioException) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      if (body is Map) {
        final code = (body['code'] as num?)?.toInt() ?? 0;
        final msg = body['message']?.toString();
        if (code == 40002) return '激活码无效';
        if (code == 40301) return '请先开通会员';
        if (code == 40101 || status == 401) return '登录已过期，请重新登录';
        if (msg != null && msg.isNotEmpty) return msg;
      }
      if (status == 401) return '登录已过期，请重新登录';
      if (status == 403) return '没有权限，请先登录账号';
      if (status == 404) return '后端接口不存在，请检查版本';
      if (status != null && status >= 500) return '服务器错误（$status）';
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.connectionError:
          return '无法连接服务器，请检查后端是否启动';
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return '请求超时，请重试';
        default:
          return '网络错误：${e.type.name}';
      }
    }
    final s = e.toString();
    if (s.contains('Connection') || s.contains('Socket')) {
      return '无法连接服务器';
    }
    return s.length > 50 ? '${s.substring(0, 50)}…' : s;
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
            child: const Icon(Icons.workspace_premium,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(status.planName ?? '会员版',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          child:
              const Icon(Icons.person_outline, color: AppTheme.muted, size: 26),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.muted)),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(child: Text('月度', style: headerStyle(AppTheme.muted))),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(child: Text('年度', style: headerStyle(AppTheme.deepBlue))),
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

// ── 激活码兑换底部弹窗 ────────────────────────────────────────

class _ActivationSheet extends StatefulWidget {
  const _ActivationSheet({
    required this.planCode,
    required this.planName,
    required this.priceLabel,
    required this.onRedeem,
  });

  final String planCode;
  final String planName;
  final String priceLabel;

  /// 返回错误文本；null 表示成功
  final Future<String?> Function(String code) onRedeem;

  @override
  State<_ActivationSheet> createState() => _ActivationSheetState();
}

class _ActivationSheetState extends State<_ActivationSheet> {
  // controller 由本组件自己创建 + dispose，避免被外部提前释放
  final TextEditingController _codeCtrl = TextEditingController();
  String? _errorText;
  bool _busy = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _doRedeem() async {
    if (_busy) return;
    final code = _codeCtrl.text.trim();
    setState(() {
      _busy = true;
      _errorText = null;
    });
    final err = await widget.onRedeem(code);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorText = err;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      // 键盘弹出时，整个 Sheet 上推（避开输入框）
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 把手条
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),

                // 标题
                Row(children: [
                  Expanded(
                    child: Text(
                      '开通${widget.planName}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context, false),
                    visualDensity: VisualDensity.compact,
                  ),
                ]),
                const SizedBox(height: 8),

                // 权益清单
                _BenefitRow(
                    icon: Icons.cloud_sync_outlined, text: '加密云同步，多端数据安全备份'),
                const SizedBox(height: 8),
                _BenefitRow(
                    icon: Icons.document_scanner_outlined,
                    text: '体检报告 OCR 智能识别'),
                const SizedBox(height: 8),
                _BenefitRow(
                    icon: Icons.psychology_outlined, text: 'AI 健康方案无限次生成'),
                if (widget.planCode == 'yearly') ...[
                  const SizedBox(height: 8),
                  _BenefitRow(
                      icon: Icons.support_agent_outlined, text: '年度专属优先客服响应'),
                ],
                const SizedBox(height: 16),

                // 价格
                Text(
                  '价格：${widget.priceLabel}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppTheme.deepBlue),
                ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // 激活码输入
                const Text('已有激活码？',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (_errorText != null) setState(() => _errorText = null);
                  },
                  onSubmitted: (_) => _doRedeem(),
                  decoration: InputDecoration(
                    hintText: widget.planCode == 'yearly'
                        ? '输入激活码（如 HEALTH365）'
                        : '输入激活码（如 HEALTH30）',
                    errorText: _errorText,
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '提示：激活码决定实际开通的套餐类型（月度/年度）',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
                const SizedBox(height: 12),

                // 兑换按钮
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _doRedeem,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('兑换激活码',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),

                const SizedBox(height: 16),
                // 在线支付占位
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.pageBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
        ),
      ),
    );
  }
}
