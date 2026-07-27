import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leb2_watch/src/core/database/app_database_manager.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/core/security/flutter_secure_credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/background_sync/application/local_background_scheduler.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_schedule_store.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/features/notifications/application/local_notification_service_impl.dart';
import 'package:leb2_watch/src/features/notifications/application/quiescence_aware_local_notification_service.dart';
import 'package:leb2_watch/src/features/notifications/data/flutter_local_notifications_adapter.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/application/local_data_deletion_service.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/data/local_data_cleanup_adapters.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';
import 'package:leb2_watch/src/platform/background/android/android_workmanager_scheduler_platform.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'support/android_native_local_data_deletion_guard.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android production delete-all clears only inert app-owned local data',
    (tester) async {
      requireAndroidNativeLocalDataDeletionTestOptIn();

      final storage = LocalDatabaseStorage();
      final databaseManager = AppDatabaseManager(storage);
      final credentials = FlutterSecureCredentialStore();
      final workmanager = AndroidWorkmanagerSchedulerPlatform();
      final notificationAdapter = FlutterLocalNotificationsAdapter();
      final notifications = QuiescenceAwareLocalNotificationService(
        LocalNotificationServiceImpl(notificationAdapter),
        storage,
      );
      final cache = OwnedLocalApplicationCacheCleanup();
      final cacheRoot = await getApplicationCacheDirectory();
      final database = await databaseManager.open();
      final scheduler = LocalBackgroundScheduler(
        DriftBackgroundScheduleStore(database),
        DriftSessionLifecycleStore(database),
        workmanager,
      );
      final coordinator = LocalDataDeletionCoordinator(
        background: PlatformLocalDataBackgroundCleanup(
          () async => scheduler,
          workmanager,
        ),
        autostart: PlatformLocalDataAutostartCleanup(
          const UnsupportedDesktopAutostartService(),
        ),
        notifications: PlatformLocalDataNotificationCleanup(
          notifications,
          notifications,
          notificationAdapter.capabilities,
        ),
        credentials: SecureLocalDataCredentialCleanup(credentials),
        database: DriftLocalDataDatabaseCleanup(databaseManager, storage),
        cache: cache,
        providerGraph: CallbackLocalProviderGraphReset(() async {}),
      );
      final databaseFile = await storage.resolveDatabaseFile();
      final ownedCache = Directory(
        path.join(
          cacheRoot.path,
          OwnedLocalApplicationCacheCleanup.ownedDirectoryName,
        ),
      );

      try {
        await credentials.saveSessionCookie('inert-local-session-sentinel');
        await credentials.saveCredentials(
          const StoredCredentials(
            username: 'inert-local-user',
            password: 'inert-local-password',
          ),
        );
        await ownedCache.create(recursive: true);
        await File(
          path.join(ownedCache.path, 'sentinel.cache'),
        ).writeAsString('inert-local-cache-sentinel');

        final result = await coordinator.deleteAll();

        expect(result.operation, LocalDataDeletionOperation.allLocalData);
        expect(result.isComplete, isTrue);
        expect(
          result.steps
              .singleWhere(
                (step) => step.step == LocalDataDeletionStep.desktopAutostart,
              )
              .status,
          LocalDataDeletionStepStatus.notApplicable,
        );
        expect(await credentials.readSessionCookie(), isNull);
        expect(await credentials.readCredentials(), isNull);
        for (final suffix in const ['', '-wal', '-shm']) {
          expect(await File('${databaseFile.path}$suffix').exists(), isFalse);
        }
        expect(await ownedCache.exists(), isFalse);

        final freshDatabase = await databaseManager.open();
        expect(
          await freshDatabase.select(freshDatabase.appSettings).get(),
          isEmpty,
        );
        await databaseManager.close();
      } finally {
        await _bestEffortCleanup(
          credentials: credentials,
          databaseManager: databaseManager,
          storage: storage,
          notifications: notifications,
          notificationAdapter: notificationAdapter,
          workmanager: workmanager,
          cache: cache,
        );
      }
    },
  );
}

Future<void> _bestEffortCleanup({
  required FlutterSecureCredentialStore credentials,
  required AppDatabaseManager databaseManager,
  required LocalDatabaseStorage storage,
  required QuiescenceAwareLocalNotificationService notifications,
  required FlutterLocalNotificationsAdapter notificationAdapter,
  required AndroidWorkmanagerSchedulerPlatform workmanager,
  required OwnedLocalApplicationCacheCleanup cache,
}) async {
  try {
    await notifications.cancelAllAfterQuiescence();
  } on Object {
    // Preserve the original test failure while attempting independent cleanup.
  }
  try {
    await workmanager.cancelPeriodicSync();
  } on Object {
    // Preserve the original test failure while attempting independent cleanup.
  }
  try {
    await credentials.clear();
  } on Object {
    // Preserve the original test failure while attempting independent cleanup.
  }
  try {
    await databaseManager.close();
  } on Object {
    // Preserve the original test failure while attempting independent cleanup.
  }
  try {
    await storage.deleteDatabaseFiles();
  } on Object {
    // Preserve the original test failure while attempting independent cleanup.
  }
  try {
    await cache.clear();
  } on Object {
    // Preserve the original test failure while attempting independent cleanup.
  }
  notifications.dispose();
  notificationAdapter.dispose();
  workmanager.dispose();
}
