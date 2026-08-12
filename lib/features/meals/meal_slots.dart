import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';

class MealSlots extends StatelessWidget {
  const MealSlots({
    super.key,
    required this.meals,
    required this.onAdd,
    required this.onEdit,
  });

  final List<MealRecordData> meals;
  final ValueChanged<String> onAdd;
  final ValueChanged<MealRecordData> onEdit;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          boxShadow:  [
            BoxShadow(
              color: AppTheme.softShadow,
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            for (final type in const [
              ('breakfast', '早餐', Icons.free_breakfast_outlined),
              ('lunch', '午餐', Icons.lunch_dining_outlined),
              ('dinner', '晚餐', Icons.dinner_dining_outlined),
            ])
              _MealSlot(
                type: type.$1,
                label: type.$2,
                icon: type.$3,
                meal:
                    meals.where((meal) => meal.mealType == type.$1).firstOrNull,
                onAdd: onAdd,
                onEdit: onEdit,
              ),
          ],
        ),
      );
}

class _MealSlot extends StatelessWidget {
  const _MealSlot({
    required this.type,
    required this.label,
    required this.icon,
    required this.meal,
    required this.onAdd,
    required this.onEdit,
  });

  final String type;
  final String label;
  final IconData icon;
  final MealRecordData? meal;
  final ValueChanged<String> onAdd;
  final ValueChanged<MealRecordData> onEdit;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(meal?.name.isNotEmpty == true ? meal!.name : '尚未记录'),
        trailing: TextButton(
          onPressed: meal == null ? () => onAdd(type) : () => onEdit(meal!),
          child: Text(meal == null ? '记录' : '查看'),
        ),
      );
}
