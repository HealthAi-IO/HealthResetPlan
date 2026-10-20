import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ClockFeedbackService {
  ClockFeedbackService._();

  static final FlutterTts _speech = FlutterTts();
  static Future<void>? _configureFuture;
  static Future<void> _speechQueue = Future<void>.value();

  static Future<void> _configure() {
    return _configureFuture ??= () async {
      await _speech.setLanguage('zh-CN');
      await _speech.setSpeechRate(0.42);
      await _speech.awaitSpeakCompletion(false);
    }();
  }

  static Future<void> _speak(String message) async {
    final task = _speechQueue.then((_) async {
      try {
        await _configure().timeout(const Duration(seconds: 3));
        await _speech.stop().timeout(const Duration(seconds: 2));
        await _speech.speak(message).timeout(const Duration(seconds: 3));
      } catch (_) {
        // 语音引擎不可用或响应超时时，不阻塞提醒界面。
      }
    });
    _speechQueue = task.catchError((_) {});
    await task;
  }

  static Future<void> acknowledge({
    required String message,
    required bool speak,
  }) async {
    await HapticFeedback.lightImpact();
    if (!speak) return;
    await _speak(message);
  }

  static Future<void> speakMedicationReminder({
    required String medicineName,
    required String dose,
    required String instructions,
  }) async {
    final details =
        [dose, instructions].where((item) => item.isNotEmpty).join('，');
    final message = details.isEmpty
        ? '您该吃药了，$medicineName'
        : '您该吃药了，$medicineName，$details';
    await _speak(message);
  }
}
