enum AppEnvironment { development, production }

final class AppConfiguration {
  const AppConfiguration._({
    required this.environment,
    required this.backendBaseUrl,
  });

  factory AppConfiguration.fromEnvironment() {
    return AppConfiguration.parse(
      appEnvironment: const String.fromEnvironment(
        'APP_ENV',
        defaultValue: 'development',
      ),
      backendBaseUrl: const String.fromEnvironment('BACKEND_BASE_URL'),
    );
  }

  factory AppConfiguration.parse({
    String appEnvironment = 'development',
    String backendBaseUrl = '',
  }) {
    return AppConfiguration._(
      environment: _parseEnvironment(appEnvironment),
      backendBaseUrl: backendBaseUrl,
    );
  }

  final AppEnvironment environment;
  final String backendBaseUrl;

  static AppEnvironment _parseEnvironment(String value) {
    return switch (value) {
      '' || 'development' => AppEnvironment.development,
      'production' => AppEnvironment.production,
      _ => throw FormatException('Unsupported APP_ENV value: $value'),
    };
  }
}
