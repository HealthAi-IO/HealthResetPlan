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
      content: const Text('使用 AI 问诊、7 天计划、报告 OCR、餐食热量、皮肤、舌象或头皮图片分析时，你主动提交的必要文本、健康摘要或图片将由本服务的受控服务器短暂转发给已配置的千问、豆包、智谱 GLM 或 DeepSeek 处理。照片可能包含面部或健康相关信息，仅用于当次分析，不用于训练；请求和回答不写入运营数据、审计日志或明文数据库，管理后台无法查看。AI 仅供健康管理参考，不能替代医生诊断。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('暂不使用')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('同意并继续')),
      ],
    ),
  );
  if (accepted != true) return false;
  await api.accept();
  return true;
}
