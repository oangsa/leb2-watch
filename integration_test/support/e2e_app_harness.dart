import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/app/leb2_watch_app.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/app/startup/app_startup_flow.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/data_deletion_dependencies.dart';

import 'recording_platforms.dart';
import 'scripted_backend_adapter.dart';

final class E2eAppHarness {
  E2eAppHarness._({
    required this.root,
    required this.storage,
    required this.configuration,
    required this.adapter,
    required this.credentials,
    required this.notifications,
    required this.background,
    required this.cacheCleanup,
  });

  final Directory root;
  final LocalDatabaseStorage storage;
  final AppConfiguration configuration;
  final ScriptedBackendAdapter adapter;
  final IntegrationCredentialStore credentials;
  final NotificationJournal notifications;
  final BackgroundJournal background;
  final IntegrationOwnedCacheCleanup cacheCleanup;

  static Future<E2eAppHarness> create({
    required ScriptedBackendAdapter adapter,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'leb2_watch_e2e_mocked_',
    );
    final supportRoot = Directory('${root.path}/support');
    final cacheRoot = Directory('${root.path}/cache');
    await supportRoot.create(recursive: true);
    await cacheRoot.create(recursive: true);
    final storage = LocalDatabaseStorage(
      applicationSupportDirectoryProvider: () async => supportRoot,
    );
    final cacheCleanup = IntegrationOwnedCacheCleanup(cacheRoot);
    await cacheCleanup.ownedDirectory.create(recursive: true);
    await File(
      '${cacheCleanup.ownedDirectory.path}/integration-owned.tmp',
    ).writeAsString('sanitized');
    return E2eAppHarness._(
      root: root,
      storage: storage,
      configuration: AppConfiguration.parse(
        appEnvironment: 'production',
        backendBaseUrl: integrationBackendBaseUrl,
      ),
      adapter: adapter,
      credentials: IntegrationCredentialStore(),
      notifications: NotificationJournal(),
      background: BackgroundJournal(),
      cacheCleanup: cacheCleanup,
    );
  }

  Future<E2eAppLifetime> pumpApp(WidgetTester tester) async {
    final initialStage = await resolveInitialAppFlowStage(
      databaseStorage: storage,
      credentialStore: credentials,
    );
    final notificationPlatform = RecordingLocalNotificationsPlatform(
      notifications,
    );
    final backgroundPlatform = RecordingBackgroundSchedulerPlatform(background);
    final client = DioBackendApiClient(
      configuration: configuration,
      credentialStore: credentials,
      httpClientAdapter: adapter,
    );
    final container = ProviderContainer(
      overrides: [
        appConfigurationProvider.overrideWithValue(configuration),
        initialAppFlowStageProvider.overrideWithValue(initialStage),
        credentialStoreProvider.overrideWithValue(credentials),
        localDatabaseStorageProvider.overrideWithValue(storage),
        backendApiClientProvider.overrideWithValue(client),
        backendSessionClientProvider.overrideWithValue(client),
        localNotificationsPlatformProvider.overrideWithValue(
          notificationPlatform,
        ),
        backgroundSchedulerPlatformProvider.overrideWithValue(
          backgroundPlatform,
        ),
        localApplicationCacheCleanupProvider.overrideWithValue(cacheCleanup),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Leb2WatchApp(configuration: configuration),
      ),
    );
    await tester.pump();
    return E2eAppLifetime._(container);
  }

  Future<AppDatabase> reopenDatabaseForInspection() => storage.openDatabase();

  Future<void> dispose() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

final class E2eAppLifetime {
  E2eAppLifetime._(this.container);

  final ProviderContainer container;
  bool _disposed = false;

  Future<AppDatabase> database() => container.read(appDatabaseProvider.future);

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await container.read(appDatabaseManagerProvider).close();
    container.dispose();
  }
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
  int maximumPumps = 240,
}) async {
  for (var attempt = 0; attempt < maximumPumps; attempt += 1) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 25));
  }
  throw TestFailure(
    reason ?? 'The expected integration state was not reached.',
  );
}
