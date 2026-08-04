const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.jkcqplan.com/api/v1',
);

const appReleaseChannel = String.fromEnvironment(
  'APP_RELEASE_CHANNEL',
  defaultValue: 'official',
);

String apiUrl(String path) {
  final base = apiBaseUrl.endsWith('/') ? apiBaseUrl : '$apiBaseUrl/';
  return Uri.parse(base).resolve(path).toString();
}
