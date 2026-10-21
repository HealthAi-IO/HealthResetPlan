import 'package:flutter/material.dart';

/// A local vector landscape, also captured when exporting the poster.
class RoutineLandscape extends CustomPainter {
  const RoutineLandscape({required this.morning});
  final bool morning;

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: morning
            ? [const Color(0xffd8eee9), const Color(0xffffe7b5)]
            : [const Color(0xff162a46), const Color(0xff49647b)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);
    final light = Offset(size.width * .73, size.height * .31);
    final radius = size.height * .14;
    if (morning) {
      canvas.drawCircle(
          light, radius * 1.45, Paint()..color = const Color(0x35fff5d6));
      canvas.drawCircle(
          light, radius, Paint()..color = const Color(0xfffff1cc));
    } else {
      final moon = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: light, radius: radius)),
        Path()
          ..addOval(Rect.fromCircle(
              center: light.translate(radius * .55, -radius * .3),
              radius: radius * .95)),
      );
      canvas.drawPath(moon, Paint()..color = const Color(0xfff3e8c8));
      for (final point in const [
        Offset(.12, .22),
        Offset(.3, .12),
        Offset(.46, .33),
        Offset(.58, .18),
        Offset(.9, .45)
      ]) {
        canvas.drawCircle(Offset(size.width * point.dx, size.height * point.dy),
            1.5, Paint()..color = const Color(0xffd6e5ee));
      }
    }
    final back = Path()
      ..moveTo(0, size.height * .68)
      ..cubicTo(size.width * .3, size.height * .28, size.width * .57,
          size.height * .9, size.width, size.height * .5)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        back,
        Paint()
          ..color =
              morning ? const Color(0xff91b8a5) : const Color(0xff29485c));
    final front = Path()
      ..moveTo(0, size.height * .84)
      ..cubicTo(size.width * .35, size.height * .99, size.width * .62,
          size.height * .46, size.width, size.height * .77)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        front,
        Paint()
          ..color =
              morning ? const Color(0xff467c70) : const Color(0xff183848));
  }

  @override
  bool shouldRepaint(covariant RoutineLandscape oldDelegate) =>
      morning != oldDelegate.morning;
}
