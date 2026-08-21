import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import 'meal_image.dart';

class MealSlots extends StatelessWidget {
  const MealSlots({
    super.key,
    required this.meals,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MealRecordData> meals;
  final ValueChanged<String> onAdd;
  final ValueChanged<MealRecordData> onEdit;
  final ValueChanged<MealRecordData> onDelete;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
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
                meals: meals.where((meal) => meal.mealType == type.$1).toList(),
                onAdd: onAdd,
                onEdit: onEdit,
                onDelete: onDelete,
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
    required this.meals,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final String type;
  final String label;
  final IconData icon;
  final List<MealRecordData> meals;
  final ValueChanged<String> onAdd;
  final ValueChanged<MealRecordData> onEdit;
  final ValueChanged<MealRecordData> onDelete;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            title: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(meals.isEmpty ? '尚未记录' : '已记录 ${meals.length} 次'),
            trailing: TextButton(
              onPressed: () => onAdd(type),
              child: Text(meals.isEmpty ? '记录' : '继续添加'),
            ),
          ),
          for (final meal in meals)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => onEdit(meal),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: meal.imagePath.isEmpty
                    ? Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        color: AppTheme.primaryBlue.withValues(alpha: 0.10),
                        child: Icon(Icons.restaurant, color: AppTheme.deepBlue),
                      )
                    : MealImage(
                        path: meal.imagePath,
                        width: 48,
                        height: 48,
                      ),
              ),
              title: Text(
                meal.name.isEmpty ? '未命名餐单' : meal.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${meal.totalCalories.round()} kcal'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '删除餐食',
                    onPressed: () => onDelete(meal),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
        ],
      );
}
