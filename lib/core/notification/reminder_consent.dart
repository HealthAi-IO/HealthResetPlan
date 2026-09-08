import 'package:flutter/material.dart';

import 'reminder_scheduler.dart';

enum ReminderConsentResult { allowed, declined, notificationsDisabled }

Future<ReminderConsentResult> confirmReminderUse(
  BuildContext context,
  ReminderScheduler scheduler,
) async {
  if (!await scheduler.hasUserConsent()) {
    if (!context.mounted) return ReminderConsentResult.declined;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('开启健康提醒'),
        content: const Text(
          'APP 将在你设定的时间发送饮食、运动、用药、称重等通知。'
          '你同意开启后，APP 可能在到达提醒时间、设备重启或应用更新后由系统唤起本地通知组件，'
          '用于发送或恢复你主动创建的提醒，不会用于广告、营销或拉起第三方应用。'
          '提醒可能受系统限制产生延迟，不用于紧急或关键医疗用途。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('暂不开启'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('同意并开启'),
          ),
        ],
      ),
    );
    if (accepted != true) return ReminderConsentResult.declined;
    await scheduler.grantUserConsent();
  }

  await scheduler.initialize();
  final granted = await scheduler.requestPermission();
  if (granted == false) return ReminderConsentResult.notificationsDisabled;
  if (await scheduler.notificationsEnabled() == false) {
    return ReminderConsentResult.notificationsDisabled;
  }
  return ReminderConsentResult.allowed;
}
