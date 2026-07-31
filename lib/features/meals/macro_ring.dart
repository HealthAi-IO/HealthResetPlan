import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

class MacroRing extends StatelessWidget {
  const MacroRing({
    super.key,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.size = 98,
  });

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(size, size),
          painter: _MacroRingPainter(
            protein: proteinG,
            carbs: carbsG,
            fat: fatG,
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(calories < 0 ? '--' : calories.round().toString(),
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const Text('kcal', style: TextStyle(color: AppTheme.muted)),
        ]),
      ]),
    );
  }
}

class _MacroRingPainter extends CustomPainter {
  const _MacroRingPainter({
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final double protein;
  final double carbs;
  final double fat;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.095;
    final bg = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(stroke), -pi / 2, pi * 2, false, bg);
    final total = max(1, protein + carbs + fat);
    var start = -pi / 2;
    for (final item in const [
      Color(0xFF19B43B),
      Color(0xFFF59E0B),
      Color(0xFFFACC15),
    ].indexed) {
      final value = switch (item.$1) {
        0 => protein,
        1 => carbs,
        _ => fat,
      };
      final sweep = pi * 2 * value / total;
      final paint = Paint()
        ..color = item.$2
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect.deflate(stroke), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _MacroRingPainter old) =>
      old.protein != protein || old.carbs != carbs || old.fat != fat;
}
