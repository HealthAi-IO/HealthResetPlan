import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../auth/user_session.dart';
import '../di/service_locator.dart';
import 'membership_service.dart';

// ── 可付费墙功能枚举 ──────────────────────────────────────────

enum PaywallFeature {
  cloudSync,
  reportOcr,
  aiPlan,
  exportData,
}

extension PaywallFeatureX on PaywallFeature {
  IconData get icon => switch (this) {
        PaywallFeature.cloudSync => Icons.cloud_sync_outlined,
        PaywallFeature.reportOcr => Icons.document_scanner_outlined,
        PaywallFeature.aiPlan => Icons.psychology_outlined,
        PaywallFeature.exportData => Icons.download_outlined,
      };

  String get title => switch (this) {
        PaywallFeature.cloudSync => '加密云同步',
        PaywallFeature.reportOcr => '报告 OCR 识别',
        PaywallFeature.aiPlan => 'AI 智能计划',
        PaywallFeature.exportData => '数据导出',
      };

  String get description => switch (this) {
        PaywallFeature.cloudSync => '多设备间安全同步健康数据，换机不丢档案',
        PaywallFeature.reportOcr => '上传体检报告图片，AI 自动提取所有指标',
        PaywallFeature.aiPlan => '基于真实指标，由大模型生成个性化饮食运动方案',
        PaywallFeature.exportData => '将健康数据导出为 CSV / PDF，自由备份',
      };
}

// ── 公共入口函数 ──────────────────────────────────────────────

/// 弹出付费墙底部弹窗。
///
/// 返回值：用户点击"去开通"并成功跳转后返回 `true`，关闭/取消返回 `false`。
/// 调用方可在返回 `true` 后重新检查会员状态，决定是否继续原操作。
Future<bool> showPaywall(
  BuildContext context,
  PaywallFeature feature,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaywallSheet(feature: feature),
  );
  return result == true;
}

/// 服务端能力的统一守卫：必须先登录账号 + 已开通会员。
///
/// 调用方在执行 AI 对话 / 云同步 / OCR 等服务端能力前调用此方法。
/// - 未登录账号：弹引导窗口，引导跳转登录页
/// - 已登录但未开通：弹付费墙
/// - 都满足：返回 true，可继续后续操作
///
/// 任意条件未满足时返回 false。
Future<bool> requireAccountAndMember(
  BuildContext context,
  PaywallFeature feature,
) async {
  // ── 1. 必须先用账号登录 ────────────────────────────────────
  if (!UserSession.instance.isAccountLogin) {
    if (!context.mounted) return false;
    final goLogin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('需要登录账号'),
        content: const Text(
          '该功能需要服务端能力支持。\n请先使用手机号或邮箱登录，再开通会员。',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去登录'),
          ),
        ],
      ),
    );
    if (goLogin != true || !context.mounted) return false;
    context.push('/login?account=1');
    return false;
  }

  // ── 2. 必须开通会员 ───────────────────────────────────────
  final membership = sl<MembershipService>();
  final isActive = await membership.isActive();
  if (isActive) return true;

  if (!context.mounted) return false;
  await showPaywall(context, feature);
  // 付费墙关闭后再次检查
  return await membership.isActive();
}

// ── 付费墙底部弹窗 ────────────────────────────────────────────

class _PaywallSheet extends StatelessWidget {
  const _PaywallSheet({required this.feature});
  final PaywallFeature feature;

  static const _benefits = [
    (Icons.cloud_sync_outlined, '加密云同步，多端安全备份'),
    (Icons.document_scanner_outlined, '体检报告 OCR 智能识别'),
    (Icons.psychology_outlined, 'AI 健康方案无限次生成'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 把手条
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 24),

          // 功能图标 + 标题
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF0277BD).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(feature.icon, color: const Color(0xFF0277BD), size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            feature.title,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.ink),
          ),
          const SizedBox(height: 6),
          Text(
            feature.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, color: AppTheme.muted, height: 1.5),
          ),
          const SizedBox(height: 24),

          // 权益列表
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.pageBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              children: [
                for (final (icon, text) in _benefits) ...[
                  Row(children: [
                    Icon(icon, size: 16, color: const Color(0xFF0277BD)),
                    const SizedBox(width: 10),
                    Text(text,
                        style: const TextStyle(fontSize: 13, color: AppTheme.ink)),
                  ]),
                  if (text != _benefits.last.$2) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 套餐横排
          Row(children: [
            Expanded(
              child: _MiniPlanCard(
                title: '月度会员',
                price: '¥18',
                unit: '/月',
                isRecommended: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniPlanCard(
                title: '年度会员',
                price: '¥98',
                unit: '/年',
                isRecommended: true,
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // 去开通按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context, true);
                context.push('/membership');
              },
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: const Text('去开通会员',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: const Color(0xFF0277BD),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 稍后再说
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后再说',
                style: TextStyle(color: AppTheme.muted, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── 迷你套餐卡 ────────────────────────────────────────────────

class _MiniPlanCard extends StatelessWidget {
  const _MiniPlanCard({
    required this.title,
    required this.price,
    required this.unit,
    required this.isRecommended,
  });

  final String title;
  final String price;
  final String unit;
  final bool isRecommended;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isRecommended ? const Color(0xFF0277BD) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRecommended
              ? const Color(0xFF0277BD)
              : AppTheme.cardBorder,
        ),
        boxShadow: isRecommended
            ? [
                BoxShadow(
                  color: const Color(0xFF0277BD).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                )
              ]
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isRecommended ? Colors.white : AppTheme.ink)),
          if (isRecommended) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('推荐',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(price,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: isRecommended ? Colors.white : const Color(0xFF0277BD))),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(unit,
                style: TextStyle(
                    fontSize: 11,
                    color: isRecommended ? Colors.white70 : AppTheme.muted)),
          ),
        ]),
      ]),
    );
  }
}

// ── 锁定遮罩（可覆盖在任意 Widget 上） ─────────────────────────

/// 包裹一个 Widget，免费用户时显示半透明锁定遮罩。
///
/// 用法：
/// ```dart
/// PaywallLock(
///   feature: PaywallFeature.reportOcr,
///   memberStatus: _memberStatus,
///   child: MyPremiumWidget(),
/// )
/// ```
class PaywallLock extends StatelessWidget {
  const PaywallLock({
    super.key,
    required this.feature,
    required this.memberStatus,
    required this.child,
  });

  final PaywallFeature feature;
  final MembershipStatus memberStatus;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (memberStatus.isActive) return child;

    return Stack(
      children: [
        // 原始内容（灰度模糊）
        Opacity(opacity: 0.35, child: child),

        // 锁定遮罩
        Positioned.fill(
          child: GestureDetector(
            onTap: () => showPaywall(context, feature),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.lock_outline,
                          color: Color(0xFF0277BD), size: 22),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0277BD),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('会员专属',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
