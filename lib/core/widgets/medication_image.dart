import 'package:flutter/material.dart';

import '../storage/report_image_storage.dart';

class MedicationImage extends StatelessWidget {
  const MedicationImage({
    super.key,
    required this.objectKey,
    required this.width,
    required this.height,
    this.onTap,
  });

  final String objectKey;
  final double width;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final provider = reportImageProvider(objectKey);
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: provider == null
          ? _MedicationImageFallback(width: width, height: height)
          : Image(
              image: provider,
              width: width,
              height: height,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  _MedicationImageFallback(width: width, height: height),
            ),
    );
    if (onTap == null || provider == null) return image;
    return Semantics(
      button: true,
      label: '查看药品图片',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: image,
      ),
    );
  }
}

class _MedicationImageFallback extends StatelessWidget {
  const _MedicationImageFallback({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.medication_outlined,
        size: (width * 0.38).clamp(24, 42).toDouble(),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

Future<void> showMedicationImagePreview(
  BuildContext context,
  String objectKey,
) async {
  final provider = reportImageProvider(objectKey);
  if (provider == null) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('药品图片'),
              trailing: IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Image(image: provider, fit: BoxFit.contain),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
