import 'package:flutter/material.dart';

import '../data/health_models.dart';
import 'medication_image.dart';

Future<String?> showMedicationReminderDialog(
  BuildContext context, {
  required ReminderData reminder,
  required DateTime scheduledAt,
  required bool seniorMode,
  required Future<void> Function() onTaken,
  required Future<void> Function() onSnooze,
  required Future<void> Function() onSkipped,
}) {
  final senior = seniorMode || MediaQuery.textScalerOf(context).scale(1) > 1.15;
  final imageObjectKey = reminder.payload['imageObjectKey']?.toString() ?? '';
  final time = reminder.dailyTimes.firstWhere(
    (value) =>
        value.hour == scheduledAt.hour && value.minute == scheduledAt.minute,
    orElse: () => reminder.dailyTimes.first,
  );
  final dose = reminder.doseAt(time);
  final instructions = reminder.instructionsAt(time);
  final detail =
      [dose, instructions].where((item) => item.isNotEmpty).join(' · ');

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: senior ? 12 : 20,
          vertical: senior ? 20 : 28,
        ),
        title: Text(
          '您该吃药了',
          style: TextStyle(
            fontSize: senior ? 28 : 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MedicationImage(
                objectKey: imageObjectKey,
                width: double.infinity,
                height: senior ? 220 : 180,
                onTap: imageObjectKey.isEmpty
                    ? null
                    : () => showMedicationImagePreview(
                          dialogContext,
                          imageObjectKey,
                        ),
              ),
              const SizedBox(height: 16),
              Text(
                reminder.displayLabel,
                style: TextStyle(
                  fontSize: senior ? 26 : 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail.isEmpty ? '请按医嘱服用并记录结果' : detail,
                style: TextStyle(
                  fontSize: senior ? 20 : 16,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: dialogContext,
                builder: (confirmContext) => AlertDialog(
                  title: const Text('确认跳过本次用药？'),
                  content: const Text('本次将记录为已跳过，不影响之后的提醒。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(confirmContext, false),
                      child: const Text('返回'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(confirmContext, true),
                      child: const Text('确认跳过'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext, 'skipped');
              await onSkipped();
            },
            child: Text(senior ? '跳过本次' : '跳过'),
          ),
          OutlinedButton(
            onPressed: () async {
              Navigator.pop(dialogContext, 'snooze');
              await onSnooze();
            },
            child: Text(senior ? '十分钟后提醒' : '稍后提醒'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext, 'taken');
              await onTaken();
            },
            child: Text(senior ? '确认已服' : '已服'),
          ),
        ],
      ),
    ),
  );
}
