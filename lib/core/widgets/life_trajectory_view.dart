import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LifeTrajectoryView extends StatelessWidget {
  const LifeTrajectoryView({
    super.key,
    required this.values,
    this.lineWidth = 5,
  });

  final List<double> values;
  final double lineWidth;

  @override
  Widget build(BuildContext context) {
    final normalizedValues = _normalize(values);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'health_reset_plan/life_trajectory',
        creationParams: {
          'values': normalizedValues,
          'lineWidth': lineWidth,
        },
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return CustomPaint(
      painter: _LifeTrajectoryPainter(
        values: normalizedValues,
        lineWidth: lineWidth,
      ),
      size: Size.infinite,
    );
  }
}

List<double> _normalize(List<double> values) {
  if (values.length < 2) return const [0.38, 0.46, 0.43, 0.56, 0.52, 0.68];
  final minValue = values.reduce((a, b) => a < b ? a : b);
  final maxValue = values.reduce((a, b) => a > b ? a : b);
  final range = maxValue - minValue;
  if (range.abs() < 0.0001) {
    return List<double>.filled(values.length, 0.5);
  }
  return values
      .map((value) => ((value - minValue) / range) * 0.58 + 0.2)
      .toList(growable: false);
}

class _LifeTrajectoryPainter extends CustomPainter {
  const _LifeTrajectoryPainter({
    required this.values,
    required this.lineWidth,
  });

  final List<double> values;
  final double lineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final points = <Offset>[
      for (var index = 0; index < values.length; index++)
        Offset(
          size.width * index / (values.length - 1),
          size.height * (0.9 - values[index] * 0.72),
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final controlX = (previous.dx + current.dx) / 2;
      path.cubicTo(
        controlX,
        previous.dy,
        controlX,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [Color(0xFF1769E0), Color(0xFF42D8CC), Color(0xFF7BE56D)],
        ).createShader(Offset.zero & size),
    );
    final endpoint = points.last;
    canvas.drawCircle(
      endpoint,
      lineWidth * 2.5,
      Paint()..color = const Color(0x337BE56D),
    );
    canvas.drawCircle(
      endpoint,
      lineWidth * 1.15,
      Paint()..color = const Color(0xFF7BE56D),
    );
  }

  @override
  bool shouldRepaint(covariant _LifeTrajectoryPainter oldDelegate) {
    return !listEquals(values, oldDelegate.values) ||
        lineWidth != oldDelegate.lineWidth;
  }
}
