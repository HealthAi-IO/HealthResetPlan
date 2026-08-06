import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/network/auth_api.dart';

Future<String?> showLoginCaptchaDialog({
  required BuildContext context,
  required AuthApi api,
  required String phone,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CaptchaDialog(api: api, phone: phone),
  );
}

class CaptchaDialog extends StatefulWidget {
  const CaptchaDialog({
    super.key,
    required this.api,
    required this.phone,
  });

  final AuthApi api;
  final String phone;

  @override
  State<CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<CaptchaDialog> {
  final Stopwatch _stopwatch = Stopwatch();
  final List<CaptchaTrajectoryPoint> _trajectory = [];

  CaptchaChallenge? _challenge;
  Uint8List? _backgroundBytes;
  Uint8List? _pieceBytes;
  double _serverX = 0;
  bool _loading = true;
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChallenge();
  }

  Future<void> _loadChallenge({bool clearError = true}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _serverX = 0;
        _trajectory.clear();
        if (clearError) _error = null;
      });
    }
    try {
      final challenge = await widget.api
          .createLoginCaptcha(phone: widget.phone)
          .timeout(const Duration(seconds: 8));
      final background = base64Decode(challenge.backgroundImageBase64);
      final piece = base64Decode(challenge.pieceImageBase64);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _backgroundBytes = background;
        _pieceBytes = piece;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyAuthError(error);
      });
    }
  }

  void _handleDragStart(DragStartDetails details) {
    if (_loading || _verifying) return;
    _serverX = 0;
    _trajectory.clear();
    _stopwatch
      ..reset()
      ..start();
    _recordPoint(details.globalPosition.dy);
    setState(() {});
  }

  void _handleDragUpdate(
    DragUpdateDetails details,
    double sliderTravel,
  ) {
    final challenge = _challenge;
    if (challenge == null || !_stopwatch.isRunning || sliderTravel <= 0) {
      return;
    }
    final imageTravel =
        (challenge.imageWidth - challenge.pieceWidth).toDouble();
    final delta = (details.primaryDelta ?? 0) / sliderTravel * imageTravel;
    setState(() {
      _serverX = (_serverX + delta).clamp(0, imageTravel);
      _recordPoint(details.globalPosition.dy);
    });
  }

  Future<void> _handleDragEnd(DragEndDetails details) async {
    if (!_stopwatch.isRunning || _verifying) return;
    _stopwatch.stop();
    _recordPoint(_trajectory.isEmpty ? 0 : _trajectory.last.y);
    final challenge = _challenge;
    if (challenge == null) return;
    if (_trajectory.length < 6 ||
        _stopwatch.elapsed < const Duration(milliseconds: 180)) {
      setState(() {
        _serverX = 0;
        _trajectory.clear();
        _error = '请对准缺口并平稳滑动后再试';
      });
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final ticket = await widget.api.verifyLoginCaptcha(
        captchaId: challenge.captchaId,
        phone: widget.phone,
        finalX: _serverX,
        trajectory: List.unmodifiable(_trajectory),
      );
      if (!mounted) return;
      Navigator.of(context).pop(ticket);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthError(error));
      await _loadChallenge(clearError: false);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _recordPoint(double y) {
    final time = _stopwatch.elapsedMilliseconds;
    if (_trajectory.isNotEmpty && time <= _trajectory.last.t) return;
    _trajectory.add(CaptchaTrajectoryPoint(x: _serverX, y: y, t: time));
  }

  @override
  Widget build(BuildContext context) {
    final challenge = _challenge;
    return AlertDialog(
      title: const Text('安全验证'),
      content: SizedBox(
        width: 320,
        child: challenge == null
            ? SizedBox(
                height: 240,
                child: Center(
                  child: _loading
                      ? const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在加载安全验证…'),
                          ],
                        )
                      : Text(
                          _error ?? '安全验证加载失败',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 10),
                  ],
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('拖动滑块，将拼图移入缺口'),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final scale = width / challenge.imageWidth;
                      return SizedBox(
                        width: width,
                        height: challenge.imageHeight * scale,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Image.memory(
                                _backgroundBytes!,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                            ),
                            Positioned(
                              left: _serverX * scale,
                              top: 0,
                              width: challenge.pieceWidth * scale,
                              height: challenge.imageHeight * scale,
                              child: Image.memory(
                                _pieceBytes!,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const thumbSize = 46.0;
                      final sliderTravel = constraints.maxWidth - thumbSize;
                      final imageTravel =
                          (challenge.imageWidth - challenge.pieceWidth)
                              .toDouble();
                      final left = imageTravel == 0
                          ? 0.0
                          : _serverX / imageTravel * sliderTravel;
                      return Container(
                        height: thumbSize,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Stack(
                          children: [
                            const Center(
                              child: Text(
                                '向右滑动',
                                style: TextStyle(color: Colors.black45),
                              ),
                            ),
                            Positioned(
                              left: left,
                              top: 0,
                              width: thumbSize,
                              height: thumbSize,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragStart: _handleDragStart,
                                onHorizontalDragUpdate: (details) =>
                                    _handleDragUpdate(details, sliderTravel),
                                onHorizontalDragEnd: _handleDragEnd,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: _verifying
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.chevron_right,
                                          color: Colors.white,
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        IconButton(
          tooltip: '换一张',
          onPressed: _loading || _verifying ? null : _loadChallenge,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}
