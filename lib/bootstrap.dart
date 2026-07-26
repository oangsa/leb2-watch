import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/app_dependencies.dart';
import 'src/app/leb2_watch_app.dart';
import 'src/app/routing/app_flow.dart';
import 'src/app/startup/app_startup_flow.dart';
import 'src/core/config/app_configuration.dart';
import 'src/core/database/local_database_storage.dart';
import 'src/core/security/credential_store.dart';
import 'src/core/security/flutter_secure_credential_store.dart';
import 'src/platform/desktop/autostart/desktop_autostart_factory.dart';
import 'src/platform/desktop/autostart/desktop_autostart_service.dart';
import 'src/platform/desktop/desktop_pre_run_app_hook.dart';

typedef AppStartupFlowResolver =
    Future<AppFlowStage> Function({
      required LocalDatabaseStorage databaseStorage,
      required CredentialStore credentialStore,
    });

Future<void> bootstrap({
  DesktopPreRunAppHook? desktopPreRunAppHook,
  LocalDatabaseStorage? databaseStorage,
  CredentialStore? credentialStore,
  AppStartupFlowResolver? startupFlowResolver,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await (desktopPreRunAppHook ?? createDesktopPreRunAppHook()).initialize();

  final configuration = AppConfiguration.fromEnvironment();
  final resolvedDatabaseStorage = databaseStorage ?? LocalDatabaseStorage();
  final resolvedCredentialStore =
      credentialStore ?? FlutterSecureCredentialStore();
  final initialStage =
      await (startupFlowResolver ?? resolveInitialAppFlowStage)(
        databaseStorage: resolvedDatabaseStorage,
        credentialStore: resolvedCredentialStore,
      );
  runApp(
    ProviderScope(
      overrides: [
        appConfigurationProvider.overrideWithValue(configuration),
        localDatabaseStorageProvider.overrideWithValue(resolvedDatabaseStorage),
        credentialStoreProvider.overrideWithValue(resolvedCredentialStore),
        initialAppFlowStageProvider.overrideWithValue(initialStage),
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
