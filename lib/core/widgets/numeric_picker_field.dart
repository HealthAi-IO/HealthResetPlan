import 'package:flutter/material.dart';

class NumericPickerResult {
  const NumericPickerResult(this.value);

  final double? value;
}

Future<NumericPickerResult?> showNumericPicker({
  required BuildContext context,
  required String title,
  required double min,
  required double max,
  required double step,
  int decimals = 0,
  double? initialValue,
  bool optional = false,
}) {
  assert(max >= min);
  assert(step > 0);
  final itemCount = ((max - min) / step).round() + 1;
  final resolvedInitial = (initialValue ?? min).clamp(min, max).toDouble();
  final initialIndex =
      ((resolvedInitial - min) / step).round().clamp(0, itemCount - 1).toInt();
  var selectedIndex = initialIndex;
  final controller = FixedExtentScrollController(initialItem: initialIndex);

  return showModalBottomSheet<NumericPickerResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final colors = Theme.of(sheetContext).colorScheme;
      final width =
          MediaQuery.sizeOf(sheetContext).width.clamp(0, 520).toDouble();
      return Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: colors.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SizedBox(
            key: const ValueKey('numeric-picker-sheet'),
            width: width,
            height: 360,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('取消'),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          NumericPickerResult(min + selectedIndex * step),
                        ),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ),
                if (optional)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: TextButton(
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          const NumericPickerResult(null),
                        ),
                        child: const Text('清空'),
                      ),
                    ),
                  ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 56,
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color:
                              colors.primaryContainer.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      ListWheelScrollView.useDelegate(
                        controller: controller,
                        itemExtent: 56,
                        diameterRatio: 1.35,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (index) => selectedIndex = index,
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: itemCount,
                          builder: (context, index) {
                            final value = min + index * step;
                            return Center(
                              child: Text(
                                value.toStringAsFixed(decimals),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
    },
  ).whenComplete(controller.dispose);
}

class NumericPickerField extends StatefulWidget {
  const NumericPickerField({
    super.key,
    required this.controller,
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    this.unit,
    this.decimals = 0,
    this.initialValue,
    this.optional = false,
    this.enabled = true,
    this.validator,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? unit;
  final double min;
  final double max;
  final double step;
  final int decimals;
  final double? initialValue;
  final bool optional;
  final bool enabled;
  final FormFieldValidator<String>? validator;
  final ValueChanged<double?>? onChanged;

  @override
  State<NumericPickerField> createState() => _NumericPickerFieldState();
}

class _NumericPickerFieldState extends State<NumericPickerField> {
  final _fieldKey = GlobalKey<FormFieldState<String>>();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant NumericPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pick() async {
    if (!widget.enabled) return;
    final currentValue = double.tryParse(widget.controller.text);
    final result = await showNumericPicker(
      context: context,
      title: widget.unit == null
          ? widget.label
          : '${widget.label}（${widget.unit}）',
      min: widget.min,
      max: widget.max,
      step: widget.step,
      decimals: widget.decimals,
      initialValue: currentValue ?? widget.initialValue,
      optional: widget.optional,
    );
    if (result == null || !mounted) return;
    final value = result.value;
    widget.controller.text = value?.toStringAsFixed(widget.decimals) ?? '';
    _fieldKey.currentState?.didChange(widget.controller.text);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = widget.controller.text.trim();
    return FormField<String>(
      key: _fieldKey,
      initialValue: value,
      validator: (_) => widget.validator?.call(widget.controller.text),
      builder: (field) => Semantics(
        button: true,
        label: widget.label,
        value: value.isEmpty ? '未选择' : '$value${widget.unit ?? ''}',
        child: InkWell(
          onTap: widget.enabled ? _pick : null,
          borderRadius: BorderRadius.circular(16),
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: field.errorText,
              enabled: widget.enabled,
              suffixIcon: const Icon(Icons.unfold_more_rounded),
            ),
            child: Text(
              value.isEmpty
                  ? (widget.optional ? '未设置' : '请选择')
                  : '$value${widget.unit == null ? '' : ' ${widget.unit}'}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: value.isEmpty
                        ? colors.onSurfaceVariant
                        : colors.onSurface,
                    fontWeight:
                        value.isEmpty ? FontWeight.w400 : FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
