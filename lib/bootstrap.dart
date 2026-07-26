import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/app_dependencies.dart';
import 'src/app/leb2_watch_app.dart';
import 'src/core/config/app_configuration.dart';
import 'src/platform/desktop/autostart/desktop_autostart_factory.dart';
import 'src/platform/desktop/autostart/desktop_autostart_service.dart';
import 'src/platform/desktop/desktop_pre_run_app_hook.dart';

Future<void> bootstrap({DesktopPreRunAppHook? desktopPreRunAppHook}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await (desktopPreRunAppHook ?? createDesktopPreRunAppHook()).initialize();

  final configuration = AppConfiguration.fromEnvironment();
  runApp(
    ProviderScope(
      overrides: [
        appConfigurationProvider.overrideWithValue(configuration),
        desktopAutostartServiceProvider.overrideWith((ref) {
          final service = createDesktopAutostartService();
          if (service is LocalDesktopAutostartService) {
            ref.onDispose(service.dispose);
          }
          return service;
        }),
      ],
      child: Leb2WatchApp(configuration: configuration),
    ),
  );
}
