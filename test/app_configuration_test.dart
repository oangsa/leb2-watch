import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';

void main() {
  group('AppConfiguration.parse', () {
    test('defaults to development with no backend URL', () {
      final configuration = AppConfiguration.parse();

      expect(configuration.environment, AppEnvironment.development);
      expect(configuration.backendBaseUrl, isEmpty);
    });

    test('treats an explicitly empty environment as development', () {
      final configuration = AppConfiguration.parse(appEnvironment: '');

      expect(configuration.environment, AppEnvironment.development);
    });

    test('accepts production and preserves the supplied backend URL', () {
      final configuration = AppConfiguration.parse(
        appEnvironment: 'production',
        backendBaseUrl: '<BACKEND_BASE_URL>',
      );

      expect(configuration.environment, AppEnvironment.production);
      expect(configuration.backendBaseUrl, '<BACKEND_BASE_URL>');
    });

    test('rejects an unsupported nonempty environment', () {
      expect(
        () => AppConfiguration.parse(appEnvironment: 'staging'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
