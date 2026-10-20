import 'api_client.dart';

class ProfileApi {
  ProfileApi({required ApiClient client}) : _client = client;
  final ApiClient _client;

  Future<Map<String, dynamic>> loadOnboardingProfile() async {
    final response = await _client.dio.get('/users/me/onboarding');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> saveOnboardingProfile({
    required String goal,
    required String gender,
    required int birthYear,
    required double heightCm,
    required double weightKg,
    required List<String> dietPreferences,
    required List<String> allergies,
    required List<String> conditions,
    required Map<String, bool> reminders,
  }) async {
    await _client.dio.put('/users/me/onboarding', data: {
      'goal': goal,
      'gender': gender,
      'birthYear': birthYear,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'dietPreferences': dietPreferences,
      'allergies': allergies,
      'conditions': conditions,
      'reminders': reminders,
    });
  }
}

