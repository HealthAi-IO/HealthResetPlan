import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/user_session.dart';

enum PaywallFeature {
  cloudSync,
  reportOcr,
  aiPlan,
  exportData,
}

/// 首版所有功能免费开放；在线能力只要求手机号账号登录。
Future<bool> requireAccountAndMember(
  BuildContext context,
  PaywallFeature feature,
) async {
  if (UserSession.instance.isAccountLogin) return true;
  if (!context.mounted) return false;

  final goLogin = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('需要登录账号'),
      content: const Text(
        '该功能需要在线服务支持，请先使用手机号登录。',
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
