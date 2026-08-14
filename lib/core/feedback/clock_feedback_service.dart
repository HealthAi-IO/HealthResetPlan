import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ClockFeedbackService {
  ClockFeedbackService._();

  static final FlutterTts _speech = FlutterTts();

  static Future<void> acknowledge({
    required String message,
    required bool speak,
  }) async {
    await HapticFeedback.lightImpact();
    if (!speak) return;
    try {
      await _speech.stop();
      await _speech.setLanguage('zh-CN');
      await _speech.setSpeechRate(0.42);
      await _speech.speak(message);
    } catch (_) {
      // 语音引擎不可用时，视觉反馈仍然有效。
    }
  }
}
