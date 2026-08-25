import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../auth/user_session.dart';
import '../network/api_response.dart';

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

bool isAiCreditError(DioException error) {
  final apiError = error.error;
  if (apiError is ApiResponseException && apiError.code == 42903) return true;
  final body = error.response?.data;
  return body is Map && (body['code'] as num?)?.toInt() == 42903;
}

Future<void> showAiCreditRequiredDialog(BuildContext context) async {
  final recharge = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('AI 健康权益已用完'),
      content: const Text(
        '充值后可继续使用报告识别、健康管家和智能分析；基础健康记录功能不受影响。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('暂不充值'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('去充值'),
        ),
      ],
    ),
  );
  if (recharge == true && context.mounted) context.push('/ai-credits');
}
