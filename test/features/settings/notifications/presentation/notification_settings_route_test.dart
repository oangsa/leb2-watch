import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/app/design_system/app_theme.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/core/network/backend_runtime_identity.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/authentication/application/logout_service.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/application/local_data_deletion_ports.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/data_deletion_dependencies.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/domain/local_data_deletion.dart';
import 'package:leb2_watch/src/features/settings/notifications/application/notification_settings_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/notification_settings_dependencies.dart';
import 'package:leb2_watch/src/features/settings/notifications/presentation/notification_settings_route.dart';

import '../support/fake_notification_settings_service.dart';

void main() {
  testWidgets('route redacts load failure and retries only on request', (
    tester,
  ) async {
    final pending = Completer<NotificationSettingsService>();
    var loadCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationSettingsServiceProvider.overrideWith((_) {
            loadCalls += 1;
            if (loadCalls == 1) {
              return pending.future;
            }
            return const FakeNotificationSettingsService();
          }),
          logoutServiceProvider.overrideWithValue(const _RouteLogoutService()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const NotificationSettingsRoute(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Preparing notification settings'), findsOneWidget);
    expect(loadCalls, 1);

    pending.completeError(StateError('<PRIVATE_SETTINGS_ERROR>'));
    await tester.pumpAndSettle();

    expect(find.text('Notification settings unavailable'), findsOneWidget);
    expect(find.textContaining('<PRIVATE_SETTINGS_ERROR>'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(loadCalls, 2);
    expect(find.byKey(const Key('notification-settings-page')), findsOneWidget);
  });

  for (final testCase in const [
    (
      key: Key('delete-cached-assignments'),
      operation: LocalDataDeletionOperation.cachedAssignments,
      stage: AppFlowStage.semesterSelection,
    ),
    (
      key: Key('delete-saved-credentials'),
      operation: LocalDataDeletionOperation.savedCredentials,
      stage: AppFlowStage.authentication,
    ),
    (
      key: Key('delete-all-local-data'),
      operation: LocalDataDeletionOperation.allLocalData,
      stage: AppFlowStage.onboarding,
    ),
  ]) {
    testWidgets('${testCase.operation.name} advances only to its safe flow', (
      tester,
    ) async {
      final flow = AppFlowController(initialStage: AppFlowStage.ready);
      addTearDown(flow.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appFlowControllerProvider.overrideWithValue(flow),
            notificationSettingsServiceProvider.overrideWith(
              (_) => const FakeNotificationSettingsService(),
            ),
            logoutServiceProvider.overrideWithValue(
              const _RouteLogoutService(),
            ),
            localDataDeletionServiceProvider.overrideWithValue(
              _CompletedDeletionService(testCase.operation),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const NotificationSettingsRoute(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('notification-settings-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Local data'),
        300,
        scrollable: scrollable,
      );
      await tester.scrollUntilVisible(
        find.byKey(testCase.key),
        80,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      final target = tester.getRect(find.byKey(testCase.key));
      await tester.tapAt(
        Offset(target.left + 20, target.top.clamp(0, 580).toDouble() + 10),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-local-data-deletion')));
      await tester.pumpAndSettle();

      expect(flow.stage, testCase.stage);
    });
  }

  for (final testCase in const [
    (
      cacheStatus: LocalDataDeletionStepStatus.completed,
      expectedStage: AppFlowStage.onboarding,
      description: 'successful real reset reaches onboarding after unmount',
    ),
    (
      cacheStatus: LocalDataDeletionStepStatus.failed,
      expectedStage: AppFlowStage.ready,
      description: 'partial real reset never advances flow',
    ),
  ]) {
    testWidgets(testCase.description, (tester) async {
      final supportDirectory = (await tester.runAsync(
        () =>
            Directory.systemTemp.createTemp('leb2-watch-real-deletion-route-'),
      ))!;
      addTearDown(() async {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      });
      final flow = AppFlowController(initialStage: AppFlowStage.ready);
      addTearDown(flow.dispose);
      final cache = _CacheCleanup(testCase.cacheStatus);
      var settingsLoadCalls = 0;
      final resetSettingsPending = Completer<NotificationSettingsService>();

      final container = ProviderContainer(
        overrides: [
          appFlowControllerProvider.overrideWithValue(flow),
          localDatabaseStorageProvider.overrideWithValue(
            LocalDatabaseStorage(
              applicationSupportDirectoryProvider: () async => supportDirectory,
            ),
          ),
          credentialStoreProvider.overrideWithValue(_CredentialStore()),
          deviceIdentityCleanupProvider.overrideWithValue(
            const _NoopDeviceIdentityCleanup(),
          ),
          backgroundSchedulerProvider.overrideWith(
            (_) async => _BackgroundScheduler(),
          ),
          localNotificationsPlatformProvider.overrideWithValue(
            _UnsupportedNotificationsPlatform(),
          ),
          localApplicationCacheCleanupProvider.overrideWithValue(cache),
          notificationSettingsServiceProvider.overrideWith((ref) async {
            settingsLoadCalls += 1;
            if (settingsLoadCalls > 1) {
              return resetSettingsPending.future;
            }
            await ref.watch(appDatabaseProvider.future);
            return const FakeNotificationSettingsService();
          }),
          logoutServiceProvider.overrideWithValue(const _RouteLogoutService()),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container
            .read(notificationSettingsServiceProvider.future)
            .timeout(const Duration(seconds: 5)),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const NotificationSettingsRoute(),
          ),
        ),
      );
      await tester.pump();

      final result = (await tester.runAsync(
        () => container
            .read(localDataDeletionFlowServiceProvider)
            .deleteAll()
            .timeout(const Duration(seconds: 15)),
      ))!;
      await tester.pump();

      expect(cache.calls, 1);
      expect(
        result.isComplete,
        testCase.cacheStatus != LocalDataDeletionStepStatus.failed,
      );
      expect(settingsLoadCalls, greaterThanOrEqualTo(2));
      expect(flow.stage, testCase.expectedStage);
    });
  }
}

final class _RouteLogoutService implements LogoutService {
  const _RouteLogoutService();

  @override
  Future<LogoutResult> logout() async => const LogoutSuccess();
}

final class _NoopDeviceIdentityCleanup implements DeviceIdentityCleanup {
  const _NoopDeviceIdentityCleanup();

  @override
  Future<DeviceIdentityCleanupResult> clearInstallationIdentity() async =>
      DeviceIdentityCleanupResult.notApplicable;
}

final class _CompletedDeletionService implements LocalDataDeletionService {
  const _CompletedDeletionService(this.expected);

  final LocalDataDeletionOperation expected;

  LocalDataDeletionResult _result(LocalDataDeletionOperation operation) {
    expect(operation, expected);
    return LocalDataDeletionResult(operation: operation, steps: const []);
  }

  @override
  Future<LocalDataDeletionResult> deleteAll() async =>
      _result(LocalDataDeletionOperation.allLocalData);

  @override
  Future<LocalDataDeletionResult> deleteCachedAssignments() async =>
      _result(LocalDataDeletionOperation.cachedAssignments);

  @override
  Future<LocalDataDeletionResult> deleteSavedCredentials() async =>
      _result(LocalDataDeletionOperation.savedCredentials);
}

final class _CacheCleanup implements LocalApplicationCacheCleanup {
  _CacheCleanup(this.status);

  final LocalDataDeletionStepStatus status;
  int calls = 0;

  @override
  Future<LocalDataDeletionStepStatus> clear() async {
    calls += 1;
    return status;
  }
}

final class _CredentialStore implements CredentialStore {
  @override
  Future<String?> readAccessKey() async => null;

  @override
  Future<void> saveAccessKey(String value) async {}

  @override
  Future<void> deleteAccessKey() async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> deleteCredentials() async {}

  @override
  Future<void> deleteSessionCookie() async {}

  @override
  Future<StoredCredentials?> readCredentials() async => null;

  @override
  Future<String?> readSessionCookie() async => null;

  @override
  Future<void> saveCredentials(StoredCredentials value) async {}

  @override
  Future<void> saveSessionCookie(String value) async {}
}

final class _BackgroundScheduler implements BackgroundScheduler {
  @override
  Future<void> cancelPeriodicSync() async {}

  @override
  Future<BackgroundScheduleStatus> getStatus() async =>
      const BackgroundScheduleInactive();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> schedulePeriodicSync() async {}
}

final class _UnsupportedNotificationsPlatform
    implements LocalNotificationsPlatform {
  @override
  LocalNotificationPlatformCapabilities get capabilities =>
      LocalNotificationPlatformCapabilities.forPlatform(
        NotificationRuntimePlatform.unsupported,
      );

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  void dispose() {}

  @override
  Future<String?> getLaunchPayload() async => null;

  @override
  Future<bool?> initialize({
    required void Function(String? payload) onResponse,
  }) async => false;

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async =>
      NotificationDeliveryPermissionStatus.blocked;

  @override
  Future<bool?> requestPermission() async => false;

  @override
  Future<void> schedule(PlatformScheduledNotification notification) async {}

  @override
  Future<void> show(PlatformNotification notification) async {}
}
