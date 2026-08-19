import 'dart:async';

import 'package:flutter/material.dart';

class MotionFadeSlide extends StatefulWidget {
  const MotionFadeSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<MotionFadeSlide> createState() => _MotionFadeSlideState();
}

class _MotionFadeSlideState extends State<MotionFadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    final curve =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero)
            .animate(curve),
        child: widget.child,
      ),
    );
  }
}
