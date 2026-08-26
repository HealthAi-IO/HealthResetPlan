import 'package:flutter/material.dart';

import '../di/service_locator.dart';
import '../network/ai_consent_api.dart';

Future<bool> ensureAiConsent(BuildContext context) async {
  final api = sl<AiConsentApi>();
  if (await api.accepted()) return true;
  if (!context.mounted) return false;
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('AI 数据处理声明'),
      content: const Text(
          '使用健康管家个性化模式时，系统会按需读取你的健康档案、近期指标、近 7 天饮食、今日计划以及你主动保存的管家记忆，并连同本次问题由受控服务器转发给通义千问生成回答。你可以切换为不读取个人数据的通用模式，也可以随时查看、修改或删除管家记忆。图片仅在你主动选择后用于对应分析，不用于训练；请求和回答不写入运营数据、审计日志或明文数据库，管理后台无法查看。AI 仅供健康管理参考，不能替代医生诊断。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('暂不使用')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意并继续')),
      ],
    ),
  );
  if (accepted != true) return false;
  try {
    await api.accept();
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 授权保存失败，请检查网络后重试')),
      );
    }
    return false;
  }
}
