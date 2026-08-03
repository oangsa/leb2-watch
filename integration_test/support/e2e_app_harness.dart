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
import 'package:leb2_watch/src/core/network/backend_compatibility.dart';
import 'package:leb2_watch/src/core/network/backend_runtime_identity.dart';
import 'package:leb2_watch/src/core/network/semantic_version.dart';
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
    required this.deviceIdentityCleanup,
  });

  final Directory root;
  final LocalDatabaseStorage storage;
  final AppConfiguration configuration;
  final ScriptedBackendAdapter adapter;
  final IntegrationCredentialStore credentials;
  final NotificationJournal notifications;
  final BackgroundJournal background;
  final IntegrationOwnedCacheCleanup cacheCleanup;
  final IntegrationDeviceIdentityCleanup deviceIdentityCleanup;

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
      deviceIdentityCleanup: IntegrationDeviceIdentityCleanup(),
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
      runtimeIdentityProvider:
          const _IntegrationBackendClientIdentityProvider(),
    );
    final container = ProviderContainer(
      overrides: [
        appConfigurationProvider.overrideWithValue(configuration),
        initialAppFlowStageProvider.overrideWithValue(initialStage),
        credentialStoreProvider.overrideWithValue(credentials),
        localDatabaseStorageProvider.overrideWithValue(storage),
        backendApiClientProvider.overrideWithValue(client),
        backendSessionClientProvider.overrideWithValue(client),
        backendCompatibilityClientProvider.overrideWithValue(
          const _IntegrationCompatibilityClient(),
        ),
        localNotificationsPlatformProvider.overrideWithValue(
          notificationPlatform,
        ),
        backgroundSchedulerPlatformProvider.overrideWithValue(
          backgroundPlatform,
        ),
        localApplicationCacheCleanupProvider.overrideWithValue(cacheCleanup),
        deviceIdentityCleanupProvider.overrideWithValue(deviceIdentityCleanup),
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

final class _IntegrationBackendClientIdentityProvider
    implements BackendClientIdentityProvider {
  const _IntegrationBackendClientIdentityProvider();

  @override
  Future<BackendClientIdentity> read() async => const BackendClientIdentity(
    device: DeviceIdentity(id: 'integration-device', platform: 'android'),
    clientVersion: '0.5.0',
  );
}

final class _IntegrationCompatibilityClient
    implements BackendCompatibilityClient {
  const _IntegrationCompatibilityClient();

  @override
  Future<BackendApiMetadata> getMetadata({
    BackendRequestCancellation? cancellation,
  }) async => BackendApiMetadata(
    apiVersion: 1,
    minimumClientVersion: SemanticVersion.parse('0.5.0'),
    latestClientVersion: SemanticVersion.parse('0.5.0'),
    downloadUrl: Uri.parse('https://downloads.example.test/latest.apk'),
  );
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
    final databaseManager = container.read(appDatabaseManagerProvider);
    container.dispose();
    await databaseManager.close();
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
