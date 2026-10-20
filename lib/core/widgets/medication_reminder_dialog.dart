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
}) async {
  final senior = seniorMode || MediaQuery.textScalerOf(context).scale(1) > 1.15;
  final dialogWidth = (MediaQuery.sizeOf(context).width - (senior ? 64 : 80))
      .clamp(240.0, 440.0)
      .toDouble();
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
  var actionProcessing = false;

  final action = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: senior ? 12 : 20,
          vertical: senior ? 20 : 28,
        ),
        child: SizedBox(
          width: dialogWidth,
          child: StatefulBuilder(
            builder: (context, setState) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '您该吃药了',
                      style: TextStyle(
                        fontSize: senior ? 28 : 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.46,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (imageObjectKey.isNotEmpty) ...[
                              MedicationImage(
                                objectKey: imageObjectKey,
                                width: dialogWidth - 48,
                                height: senior ? 160 : 128,
                                onTap: () => showMedicationImagePreview(
                                  dialogContext,
                                  imageObjectKey,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ] else ...[
                              Container(
                                height: senior ? 76 : 64,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.medication_outlined,
                                      size: senior ? 32 : 28,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '暂无药品图片',
                                      style: TextStyle(
                                        fontSize: senior ? 18 : 15,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Text(
                              reminder.displayLabel,
                              style: TextStyle(
                                fontSize: senior ? 26 : 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
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
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: actionProcessing
                          ? null
                          : () async {
                              setState(() => actionProcessing = true);
                              Navigator.pop(dialogContext, 'taken');
                            },
                      child: Text(senior ? '确认已服' : '已服'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: actionProcessing
                                ? null
                                : () async {
                                    final confirmed = await showDialog<bool>(
                                      context: dialogContext,
                                      builder: (confirmContext) => AlertDialog(
                                        title: const Text('确认跳过本次用药？'),
                                        content:
                                            const Text('本次将记录为已跳过，不影响之后的提醒。'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(
                                                confirmContext, false),
                                            child: const Text('返回'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(
                                                confirmContext, true),
                                            child: const Text('确认跳过'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed != true) return;
                                    if (!dialogContext.mounted) return;
                                    setState(() => actionProcessing = true);
                                    Navigator.pop(dialogContext, 'skipped');
                                  },
                            child: Text(senior ? '跳过本次' : '跳过'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: actionProcessing
                                ? null
                                : () async {
                                    setState(() => actionProcessing = true);
                                    Navigator.pop(dialogContext, 'snooze');
                                  },
                            child: Text(senior ? '十分钟后提醒' : '稍后提醒'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  if (action == 'taken') {
    await onTaken();
  } else if (action == 'skipped') {
    await onSkipped();
  } else if (action == 'snooze') {
    await onSnooze();
  }
  return action;
}
