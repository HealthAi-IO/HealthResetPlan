import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/health_models.dart';
import '../data/health_repository.dart';
import '../network/ai_api.dart';

enum AiPlanGenerationStatus { idle, generating, completed, failed }

class AiPlanGenerationController extends ChangeNotifier {
  AiPlanGenerationController({
    required HealthRepository repository,
    required AiApi aiApi,
  })  : _repository = repository,
        _aiApi = aiApi;

  final HealthRepository _repository;
  final AiApi _aiApi;

  AiPlanGenerationStatus status = AiPlanGenerationStatus.idle;
  AiPlanResult? result;
  Object? error;
  bool usedLocalFallback = false;
  int eventId = 0;
  Future<void>? _task;

  bool get isGenerating => status == AiPlanGenerationStatus.generating;

  Future<void> start({
    required UserProfileData profile,
    required String provider,
    required String goal,
    String goalDetail = '',
    DateTime? targetDate,
  }) {
    if (isGenerating) return _task ?? Future<void>.value();

    status = AiPlanGenerationStatus.generating;
    result = null;
    error = null;
    usedLocalFallback = false;
    notifyListeners();

    final task = _run(
      profile: profile,
      provider: provider,
      goal: goal,
      goalDetail: goalDetail,
      targetDate: targetDate,
    );
    _task = task;
    return task;
  }

  Future<void> _run({
    required UserProfileData profile,
    required String provider,
    required String goal,
    required String goalDetail,
    required DateTime? targetDate,
  }) async {
    try {
      final indicators = await _repository.loadIndicators(limit: 20);
      result = await _aiApi
          .generatePlan(
            profile: profile,
            recentIndicators: indicators,
            provider: provider,
            goal: goal,
            goalDetail: goalDetail,
            targetDate: targetDate,
          )
          .timeout(const Duration(seconds: 130));
      status = AiPlanGenerationStatus.completed;
    } catch (caughtError) {
      error = caughtError;
      try {
        final localPlan = await _repository.buildLocalWeeklyPlanPreview(
          goal: goal,
          goalDetail: goalDetail,
          targetDate: targetDate,
        );
        result = AiPlanResult(
          provider: '本地安全方案',
          rawJson: jsonEncode(localPlan),
        );
        usedLocalFallback = true;
        status = AiPlanGenerationStatus.completed;
      } catch (_) {
        status = AiPlanGenerationStatus.failed;
      }
    } finally {
      _task = null;
      eventId++;
      notifyListeners();
    }
  }

  void clear() {
    if (isGenerating) return;
    status = AiPlanGenerationStatus.idle;
    result = null;
    error = null;
    usedLocalFallback = false;
    notifyListeners();
  }
}
