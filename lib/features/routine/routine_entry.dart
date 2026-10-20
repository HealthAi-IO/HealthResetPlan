import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RoutineEntry extends StatelessWidget {
  const RoutineEntry({super.key});
  @override
  Widget build(BuildContext context) => Card(
          child: ListTile(
        minVerticalPadding: 16,
        leading: const Icon(Icons.wb_twilight_outlined),
        title: const Text('早晚安 · 作息重启'),
        subtitle: const Text('起床与睡前打卡，回看你的休息节奏'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/routine'),
      ));
}
