import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RoutineEntry extends StatelessWidget {
  const RoutineEntry({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/routine'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.wb_twilight_outlined, color: colors.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('早晚安', style: TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('记录作息，了解休息节奏', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
