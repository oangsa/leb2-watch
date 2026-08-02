import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';
import 'package:leb2_watch/src/features/notifications/data/new_assignment_notification_store.dart';
import 'package:leb2_watch/src/features/settings/data_deletion/data_deletion_dependencies.dart';

import 'support/e2e_app_harness.dart';
import 'support/sanitized_backend_fixtures.dart';
import 'support/scripted_backend_adapter.dart';

const _cookieA = '<SESSION_COOKIE_A>';
const _cookieB = '<SESSION_COOKIE_B>';
const _accessKey = '00000000-0000-4000-8000-000000000001';
const _baselineCardKey = Key('assignment-card-101-backend:1001');
const _newAssignmentCardKey = Key('assignment-card-101-backend:1002');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'onboards, synchronizes local-first, recovers, and deletes all data',
    (tester) async {
      final releaseRestartSync = Completer<void>();
      final releaseAutomaticLogin = Completer<void>();
      final adapter = ScriptedBackendAdapter([
        ScriptedBackendExchange(
          method: 'POST',
          path: '/User/login',
          accessKey: _accessKey,
          authorization: null,
          requestBody: sanitizedCredentialsRequest,
          body: sanitizedUserProfileFixture,
        ),
        ScriptedBackendExchange(
          method: 'POST',
          path: '/User/cookie',
          accessKey: _accessKey,
          authorization: null,
          requestBody: sanitizedCredentialsRequest,
          body: sanitizedCookieFixture(_cookieA),
        ),
        ScriptedBackendExchange(
          method: 'GET',
          path: '/Semester',
          accessKey: _accessKey,
          authorization: 'Bearer $_cookieA',
          body: sanitizedSemestersFixture,
        ),
        ScriptedBackendExchange(
          method: 'GET',
          path: '/Semester',
          accessKey: _accessKey,
          authorization: 'Bearer $_cookieA',
          body: sanitizedSemestersFixture,
        ),
        ScriptedBackendExchange(
          method: 'GET',
          path: '/Activity/101/snapshot',
          accessKey: _accessKey,
          authorization: 'Bearer $_cookieA',
          userId: '2001',
          body: sanitizedSnapshotFixture(includeNewAssignment: false),
        ),
        ScriptedBackendExchange(
          method: 'GET',
          path: '/Activity/101/snapshot',
          accessKey: _accessKey,
          authorization: 'Bearer $_cookieA',
          userId: '2001',
          body: sanitizedSnapshotFixture(includeNewAssignment: true),
          release: releaseRestartSync.future,
        ),
        ScriptedBackendExchange(
          method: 'GET',
          path: '/Activity/101/snapshot',
          accessKey: _accessKey,
          authorization: 'Bearer $_cookieA',
          userId: '2001',
          body: sanitizedSessionExpiredFixture,
          statusCode: 401,
          additionalHeaders: const {
            'www-authenticate': ['Bearer'],
          },
        ),
        ScriptedBackendExchange(
          method: 'POST',
          path: '/User/login',
          accessKey: _accessKey,
          authorization: null,
          requestBody: sanitizedCredentialsRequest,
          body: sanitizedUserProfileFixture,
          release: releaseAutomaticLogin.future,
        ),
        ScriptedBackendExchange(
          method: 'POST',
          path: '/User/cookie',
          accessKey: _accessKey,
          authorization: null,
          requestBody: sanitizedCredentialsRequest,
          body: sanitizedCookieFixture(_cookieB),
        ),
        ScriptedBackendExchange(
          method: 'GET',
          path: '/Semester',
          accessKey: _accessKey,
          authorization: 'Bearer $_cookieB',
          body: sanitizedSemestersFixture,
        ),
        ScriptedBackendExchange(
          method: 'GET',
          path: '/Activity/101/snapshot',
          accessKey: _accessKey,
          authorization: 'Bearer $_cookieB',
          userId: '2001',
          body: sanitizedSnapshotFixture(includeNewAssignment: true),
        ),
      ]);
      final harness = await E2eAppHarness.create(adapter: adapter);
      E2eAppLifetime? lifetime;

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        if (!releaseRestartSync.isCompleted) {
          releaseRestartSync.complete();
        }
        if (!releaseAutomaticLogin.isCompleted) {
          releaseAutomaticLogin.complete();
        }
        await lifetime?.dispose(tester);
        await harness.dispose();
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      lifetime = await harness.pumpApp(tester);

      expect(find.text('Assignments, ready when you are'), findsOneWidget);
      expect(adapter.requestCount, 0);
      expect(harness.credentials.mutationCount, 0);
      expect(harness.notifications.permissionRequestCount, 0);

      for (var step = 0; step < 5; step += 1) {
        await tester.tap(find.byKey(const Key('onboarding-primary-button')));
        await tester.pump();
      }
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('session-method-control'))
            .evaluate()
            .isNotEmpty,
        reason: 'Onboarding did not open session setup.',
      );
      expect(adapter.requestCount, 0);
      expect(harness.credentials.mutationCount, 0);
      expect(harness.notifications.permissionRequestCount, 0);

      await tester.tap(find.text('Username / password'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('session-access-key-field')),
        _accessKey,
      );
      await tester.enterText(
        find.byKey(const Key('session-username-field')),
        '<USERNAME>',
      );
      await tester.enterText(
        find.byKey(const Key('session-password-field')),
        '<PASSWORD>',
      );
      final automaticToggle = find.byKey(
        const Key('automatic-reauthentication-toggle'),
      );
      await tester.ensureVisible(automaticToggle);
      await tester.tap(automaticToggle);
      final sessionSubmit = find.byKey(const Key('session-submit'));
      await tester.ensureVisible(sessionSubmit);
      await tester.tap(sessionSubmit);
      await pumpUntil(
        tester,
        () =>
            adapter.failure != null ||
            find.byKey(const Key('semester-row-101')).evaluate().isNotEmpty,
        reason: 'Verified session did not load the sanitized semesters.',
      );
      expect(
        adapter.failure,
        isNull,
        reason: 'The strict backend adapter rejected a session request.',
      );
      expect(adapter.requestCount, 4);
      expect(harness.credentials.accessKey, _accessKey);
      expect(harness.credentials.sessionCookie, _cookieA);
      expect(
        harness.credentials.credentials,
        const StoredCredentials(username: '<USERNAME>', password: '<PASSWORD>'),
      );

      await tester.tap(find.byKey(const Key('semester-row-101')));
      await pumpUntil(
        tester,
        () => find.byKey(_baselineCardKey).evaluate().isNotEmpty,
        reason: 'The baseline assignment was not rendered.',
      );
      await pumpUntil(
        tester,
        () => adapter.requestCount == 5,
        reason: 'The baseline snapshot was not requested.',
      );
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('assignment-inline-progress'))
            .evaluate()
            .isEmpty,
        reason: 'The baseline synchronization did not finish.',
      );

      var database = await lifetime.database();
      expect(await database.select(database.activities).get(), hasLength(1));
      final baselineSeen = await database
          .select(database.seenActivities)
          .getSingle();
      expect(baselineSeen.identityKey, 'backend:1001');
      expect(baselineSeen.isBaseline, isTrue);
      expect(
        await database.select(database.notificationHistory).get(),
        isEmpty,
      );
      expect(harness.notifications.newAssignments, isEmpty);
      final monitoring = await lifetime.container.read(
        backgroundMonitoringSettingsServiceProvider.future,
      );
      await monitoring.setMonitoringEnabled(true);
      expect(harness.background.scheduleCount, greaterThan(0));

      await lifetime.dispose(tester);
      lifetime = await harness.pumpApp(tester);
      await pumpUntil(
        tester,
        () =>
            adapter.requestCount == 6 &&
            find.byKey(_baselineCardKey).evaluate().isNotEmpty &&
            find
                .byKey(const Key('assignment-inline-progress'))
                .evaluate()
                .isNotEmpty,
        reason: 'Cache was not visible while restart synchronization waited.',
      );
      expect(find.byKey(_newAssignmentCardKey), findsNothing);
      expect(find.text('Loading saved assignments'), findsNothing);
      expect(harness.notifications.newAssignments, isEmpty);

      releaseRestartSync.complete();
      await pumpUntil(
        tester,
        () =>
            find.byKey(_newAssignmentCardKey).evaluate().isNotEmpty &&
            harness.notifications.newAssignments.length == 1,
        reason: 'The new assignment was not persisted and notified once.',
      );

      database = await lifetime.database();
      expect(await database.select(database.activities).get(), hasLength(2));
      final newSeen = await (database.select(
        database.seenActivities,
      )..where((row) => row.identityKey.equals('backend:1002'))).getSingle();
      expect(newSeen.isBaseline, isFalse);
      final notificationHistory = await database
          .select(database.notificationHistory)
          .get();
      expect(notificationHistory, hasLength(1));
      expect(notificationHistory.single.kind, newAssignmentNotificationKind);

      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('assignment-inline-progress'))
            .evaluate()
            .isEmpty,
        reason: 'The new-assignment synchronization did not finish.',
      );
      final cancellationCountBeforeExpiry = harness.background.cancelCount;
      await tester.tap(find.byKey(const Key('assignment-refresh-button')));
      await pumpUntil(
        tester,
        () =>
            adapter.failure != null ||
            adapter.requestCount == 8 &&
                find
                    .byKey(const Key('session-expired-banner'))
                    .evaluate()
                    .isNotEmpty,
        reason: 'Exact SESSION_EXPIRED did not expose reconnect state.',
      );
      expect(
        adapter.failure,
        isNull,
        reason: 'The strict backend adapter rejected the expiry request.',
      );
      expect(find.byKey(_baselineCardKey), findsOneWidget);
      expect(
        find.byKey(const Key('assignment-dashboard-list')),
        findsOneWidget,
      );
      final expiredSettings = await database
          .select(database.appSettings)
          .getSingle();
      expect(
        expiredSettings.sessionLifecycle,
        SessionLifecycleState.expired.name,
      );
      expect(await database.select(database.activities).get(), hasLength(2));
      expect(
        find.text(
          'Your LEB2 session expired. Reconnecting securely… '
          'Saved data remains available.',
        ),
        findsOneWidget,
      );
      final scheduleCountBeforeRecovery = harness.background.scheduleCount;
      releaseAutomaticLogin.complete();
      await pumpUntil(
        tester,
        () =>
            adapter.requestCount == 11 &&
            find.byKey(_newAssignmentCardKey).evaluate().isNotEmpty,
        reason: 'Automatic recovery did not resume assignment monitoring.',
      );
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('assignment-inline-progress'))
            .evaluate()
            .isEmpty,
        reason: 'Replacement-session synchronization did not finish.',
      );
      expect(harness.credentials.sessionCookie, _cookieB);
      final activeSettings = await database
          .select(database.appSettings)
          .getSingle();
      expect(
        activeSettings.sessionLifecycle,
        SessionLifecycleState.active.name,
      );
      expect(
        activeSettings.sessionRevision,
        greaterThan(expiredSettings.sessionRevision),
      );
      expect(
        harness.background.cancelCount,
        greaterThan(cancellationCountBeforeExpiry),
      );
      expect(
        harness.background.scheduleCount,
        greaterThan(scheduleCountBeforeRecovery),
      );
      final attempts = await database
          .select(database.automaticSessionReauthenticationAttempts)
          .get();
      expect(attempts, hasLength(1));
      expect(attempts.single.state, 'succeeded');
      final requestCountAfterRecovery = adapter.requestCount;
      final automatic = await lifetime.container.read(
        automaticSessionReauthenticationServiceProvider.future,
      );
      expect(
        await automatic.reauthenticate(
          expectedExpiredRevision: expiredSettings.sessionRevision,
        ),
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.superseded,
        ),
      );
      expect(adapter.requestCount, requestCountAfterRecovery);
      expect(harness.notifications.newAssignments, hasLength(1));
      expect(
        await database.select(database.notificationHistory).get(),
        hasLength(1),
      );

      final settingsDestination = find
          .byKey(const Key('compact-settings'))
          .hitTestable();
      await pumpUntil(
        tester,
        () => settingsDestination.evaluate().isNotEmpty,
        reason: 'The recovered application shell did not become interactive.',
      );
      await tester.tap(settingsDestination);
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('notification-settings-list'))
            .evaluate()
            .isNotEmpty,
        reason: 'Settings did not open.',
      );
      final deleteAllAction = find.byKey(const Key('delete-all-local-data'));
      for (
        var scroll = 0;
        scroll < 12 && deleteAllAction.evaluate().isEmpty;
        scroll += 1
      ) {
        await tester.drag(
          find.byKey(const Key('notification-settings-list')),
          const Offset(0, -300),
        );
        await tester.pump();
      }
      expect(deleteAllAction, findsOneWidget);
      await tester.ensureVisible(deleteAllAction);
      final visibleDeleteAllAction = deleteAllAction.hitTestable();
      await pumpUntil(
        tester,
        () => visibleDeleteAllAction.evaluate().isNotEmpty,
        reason: 'The delete-all action did not become interactive.',
      );
      final backgroundCancellationsBeforeDelete =
          harness.background.cancelCount;
      await tester.tap(visibleDeleteAllAction);
      await tester.pump();
      expect(find.byKey(const Key('confirm-allLocalData')), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-local-data-deletion')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('onboarding-primary-button'))
            .evaluate()
            .isNotEmpty,
        reason: 'Completed delete-all did not return to onboarding.',
        maximumPumps: 600,
      );

      expect(harness.credentials.sessionCookie, isNull);
      expect(harness.credentials.accessKey, isNull);
      expect(harness.credentials.credentials, isNull);
      expect(harness.credentials.clearCount, 1);
      expect(harness.notifications.cancelAllCount, 1);
      expect(harness.notifications.permissionRequestCount, 0);
      expect(harness.notifications.shown, hasLength(1));
      expect(harness.notifications.scheduled, isEmpty);
      expect(harness.notifications.cancelledIds, isEmpty);
      expect(harness.background.scheduleCount, greaterThan(0));
      expect(
        harness.background.cancelCount,
        greaterThan(backgroundCancellationsBeforeDelete),
      );
      expect(await harness.cacheCleanup.ownedDirectory.exists(), isFalse);
      expect(find.byKey(_baselineCardKey), findsNothing);
      expect(find.byKey(_newAssignmentCardKey), findsNothing);

      await lifetime.dispose(tester);
      lifetime = null;
      final freshDatabase = await harness.reopenDatabaseForInspection();
      try {
        expect(
          await freshDatabase.select(freshDatabase.semesters).get(),
          isEmpty,
        );
        expect(
          await freshDatabase.select(freshDatabase.activities).get(),
          isEmpty,
        );
        expect(
          await freshDatabase.select(freshDatabase.notificationHistory).get(),
          isEmpty,
        );
        expect(
          await freshDatabase.select(freshDatabase.appSettings).get(),
          isEmpty,
        );
        final backgroundDefaults = await freshDatabase
            .select(freshDatabase.backgroundScheduleSettings)
            .getSingle();
        expect(backgroundDefaults.monitoringEnabled, isFalse);
      } finally {
        await freshDatabase.close();
      }

      adapter.verifyComplete();
      expect(adapter.failure, isNull);
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'credential deletion during a gated candidate prevents late commit',
    (tester) async {
      final releaseCookie = Completer<void>();
      final adapter = ScriptedBackendAdapter([
        ScriptedBackendExchange(
          method: 'POST',
          path: '/User/login',
          accessKey: _accessKey,
          authorization: null,
          requestBody: sanitizedCredentialsRequest,
          body: sanitizedUserProfileFixture,
        ),
        ScriptedBackendExchange(
          method: 'POST',
          path: '/User/cookie',
          accessKey: _accessKey,
          authorization: null,
          requestBody: sanitizedCredentialsRequest,
          body: sanitizedCookieFixture(_cookieB),
          release: releaseCookie.future,
        ),
      ]);
      final harness = await E2eAppHarness.create(adapter: adapter);
      E2eAppLifetime? lifetime;
      final seed = await harness.reopenDatabaseForInspection();
      await seed
          .into(seed.semesters)
          .insert(SemestersCompanion.insert(semesterId: const Value(101)));
      await seed
          .into(seed.appSettings)
          .insert(
            const AppSettingsCompanion(
              singletonId: Value(1),
              activeSemesterId: Value(101),
              leb2UserId: Value(2001),
              sessionLifecycle: Value('expired'),
              sessionRevision: Value(7),
            ),
          );
      await seed.close();
      harness.credentials
        ..accessKey = _accessKey
        ..sessionCookie = _cookieA
        ..credentials = const StoredCredentials(
          username: '<USERNAME>',
          password: '<PASSWORD>',
        );
      addTearDown(() async {
        if (!releaseCookie.isCompleted) {
          releaseCookie.complete();
        }
        await lifetime?.dispose(tester);
        await harness.dispose();
      });

      lifetime = await harness.pumpApp(tester);
      await pumpUntil(
        tester,
        () => adapter.requestCount == 2,
        reason: 'Automatic recovery did not reach cookie acquisition.',
      );
      final deletion = lifetime.container.read(
        localDataDeletionServiceProvider,
      );
      final result = await deletion.deleteSavedCredentials();
      expect(result.isComplete, isTrue);
      releaseCookie.complete();
      await tester.pump(const Duration(milliseconds: 50));

      final database = await lifetime.database();
      var attempts = await database
          .select(database.automaticSessionReauthenticationAttempts)
          .get();
      for (
        var pump = 0;
        pump < 80 && (attempts.isEmpty || attempts.single.state == 'running');
        pump += 1
      ) {
        await tester.pump(const Duration(milliseconds: 10));
        attempts = await database
            .select(database.automaticSessionReauthenticationAttempts)
            .get();
      }
      expect(attempts, hasLength(1));
      expect(attempts.single.state, 'cancelled');
      expect(harness.credentials.sessionCookie, isNull);
      expect(harness.credentials.credentials, isNull);
      expect(adapter.requestCount, 2);
      adapter.verifyComplete();
      expect(adapter.failure, isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
