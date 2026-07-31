import 'package:flutter/material.dart';

class GenderSelector extends StatelessWidget {
  const GenderSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.focusNode,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      child: InkWell(
        onTap: () => _showPicker(context),
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: '性别',
            suffixIcon: Icon(Icons.keyboard_arrow_down),
          ),
          child: Text(
            _label(value),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择性别',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '用于计算更适合你的健康指标和计划建议',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              for (final option in const [
                ('female', '女', Icons.female_outlined),
                ('male', '男', Icons.male_outlined),
                ('unknown', '暂不填写', Icons.remove_circle_outline),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: value == option.$1
                        ? colors.primaryContainer
                        : colors.surfaceContainerLowest,
                    leading: Icon(
                      option.$3,
                      color: value == option.$1
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    title: Text(
                      option.$2,
                      style: TextStyle(
                        fontWeight: value == option.$1
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: value == option.$1
                        ? Icon(Icons.check_circle, color: colors.primary)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, option.$1),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (selected != null && selected != value) onChanged(selected);
  }

  String _label(String gender) {
    return switch (gender) {
      'female' => '女',
      'male' => '男',
      _ => '暂不填写',
    };
  }
}
