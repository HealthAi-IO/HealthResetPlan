import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_theme.dart';

const aiContentLabel = 'AI生成内容';

class AiContentNotice extends StatelessWidget {
  const AiContentNotice({super.key, required this.feature});

  final String feature;

  Future<void> _reportIssue(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: '87103978@qq.com',
      queryParameters: {
        'subject': '健康重启计划 AI内容反馈 - $feature',
        'body': 'AI功能：$feature\n问题描述：\n\n请勿在邮件中填写身份证号、病历原文等敏感信息。',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法打开邮件客户端，请联系 87103978@qq.com')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.08),
        border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.auto_awesome, size: 14, color: AppTheme.deepBlue),
        const SizedBox(width: 5),
        const Expanded(
          child: Text(aiContentLabel,
              style: TextStyle(
                  color: AppTheme.deepBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        TextButton(
          onPressed: () => _reportIssue(context),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('反馈', style: TextStyle(fontSize: 11)),
        ),
      ]),
    );
  }
}
