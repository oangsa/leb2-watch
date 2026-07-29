import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/app/leb2_watch_app.dart';
import 'package:leb2_watch/src/app/routing/app_flow.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_preferences.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_service.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/data/assignment_dashboard_store.dart';
import 'package:leb2_watch/src/features/assignments/detail/application/assignment_detail_service.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_monitoring_lifecycle.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_sync_target_store.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/authentication/application/automatic_session_reauthentication_service.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';
import 'package:leb2_watch/src/features/notifications/application/desktop_deadline_reminder_delivery_coordinator.dart';
import 'package:leb2_watch/src/features/notifications/data/desktop_deadline_reminder_delivery_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_service.dart';
import 'package:leb2_watch/src/features/notifications/application/new_assignment_notification_drain.dart';
import 'package:leb2_watch/src/platform/desktop/runtime/desktop_window_reveal_signal.dart';

void main() {
  testWidgets(
    'app initializes notification navigation and opens explicit assignment',
    (tester) async {
      final flow = AppFlowController(initialStage: AppFlowStage.ready);
      final notifications = _AppNotificationService();
      final drain = _AppNotificationDrain();
      final events = <String>[];
      final details = _AppAssignmentDetailService(events: events);
      final windowReveal = DesktopWindowRevealSignal();
      final revealSubscription = windowReveal.requests.listen((_) {
        events.add('window.reveal');
      });
      addTearDown(flow.dispose);
      addTearDown(notifications.dispose);
      addTearDown(revealSubscription.cancel);
      addTearDown(windowReveal.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appFlowControllerProvider.overrideWithValue(flow),
            localNotificationServiceProvider.overrideWithValue(notifications),
            desktopWindowRevealSignalProvider.overrideWithValue(windowReveal),
            newAssignmentNotificationDrainProvider.overrideWith(
              (_) async => drain,
            ),
            assignmentDashboardServiceProvider.overrideWith(
              (_) => _AppAssignmentDashboardService(),
            ),
            assignmentDetailServiceProvider.overrideWith((_) => details),
            sessionLifecycleProvider.overrideWith(
              (_) => Stream.value(
                const SessionLifecycleSnapshot(
                  state: SessionLifecycleState.active,
                  revision: 1,
                ),
              ),
            ),
          ],
          child: Leb2WatchApp(configuration: AppConfiguration.parse()),
        ),
      );
      await tester.pumpAndSettle();

      expect(notifications.initializeCalls, 1);
      expect(drain.calls, 1);
      final target = AssignmentDetailKey(
        semesterId: 999,
        identityKey: 'backend:777',
      );
      notifications.emit(LocalNotificationTarget.assignment(target));
      await tester.pumpAndSettle();

      expect(details.keys, <AssignmentDetailKey>[target]);
      expect(events, ['window.reveal', 'route:${target.identityKey}']);
      expect(
        find.text('This assignment is not saved on this device.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      notifications.emit(
        LocalNotificationTarget.assignment(
          AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001'),
        ),
      );
      flow.updateStage(AppFlowStage.authentication);
      await tester.pump();

      expect(details.keys, <AssignmentDetailKey>[target]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cold launch target waits through app flow and opens once', (
    tester,
  ) async {
    final flow = AppFlowController();
    final target = AssignmentDetailKey(
      semesterId: 999,
      identityKey: 'backend:777',
    );
    final notifications = _AppNotificationService(
      launchTarget: LocalNotificationTarget.assignment(target),
    );
    final details = _AppAssignmentDetailService();
    addTearDown(flow.dispose);
    addTearDown(notifications.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appFlowControllerProvider.overrideWithValue(flow),
          localNotificationServiceProvider.overrideWithValue(notifications),
          newAssignmentNotificationDrainProvider.overrideWith(
            (_) async => _AppNotificationDrain(),
          ),
          assignmentDashboardServiceProvider.overrideWith(
            (_) => _AppAssignmentDashboardService(),
          ),
          assignmentDetailServiceProvider.overrideWith((_) => details),
          sessionLifecycleProvider.overrideWith(
            (_) => Stream.value(
              const SessionLifecycleSnapshot(
                state: SessionLifecycleState.active,
                revision: 1,
              ),
            ),
          ),
        ],
        child: Leb2WatchApp(configuration: AppConfiguration.parse()),
      ),
    );
    await tester.pumpAndSettle();
    expect(details.keys, isEmpty);

    flow.updateStage(AppFlowStage.authentication);
    await tester.pump();
    flow.updateStage(AppFlowStage.semesterSelection);
    await tester.pump();
    expect(details.keys, isEmpty);

    flow.updateStage(AppFlowStage.ready);
    await tester.pumpAndSettle();

    expect(details.keys, <AssignmentDetailKey>[target]);
  });

  testWidgets('root lifecycle reconciles session and refreshes on resume', (
    tester,
  ) async {
    final flow = AppFlowController();
    final notifications = _AppNotificationService();
    final sessions = StreamController<SessionLifecycleSnapshot>();
    final reconciler = _AppBackgroundReconciler();
    final sync = _AppSyncService();
    final statusRefreshes = BackgroundScheduleStatusRefreshSignal();
    final automatic = _AppAutomaticReauthenticationService();
    final deadlineStore = _AppDeadlineDeliveryStore();
    final deadlineDelivery = DesktopDeadlineReminderDeliveryCoordinator(
      deadlineStore,
      notifications,
      runWithActivityLease: <T>(action) => action(),
    );
    var statusRefreshRequests = 0;
    final statusRefreshSubscription = statusRefreshes.requests.listen((_) {
      statusRefreshRequests += 1;
    });
    final lifecycle = BackgroundMonitoringLifecycle(
      reconciler,
      BackgroundSyncRunner(const _AppBackgroundTargetStore(), sync),
    );
    addTearDown(flow.dispose);
    addTearDown(notifications.dispose);
    addTearDown(sessions.close);
    addTearDown(statusRefreshSubscription.cancel);
    addTearDown(statusRefreshes.dispose);
    addTearDown(deadlineDelivery.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appFlowControllerProvider.overrideWithValue(flow),
          localNotificationServiceProvider.overrideWithValue(notifications),
          newAssignmentNotificationDrainProvider.overrideWith(
            (_) async => _AppNotificationDrain(),
          ),
          sessionLifecycleProvider.overrideWith((_) => sessions.stream),
          backgroundMonitoringLifecycleProvider.overrideWith(
            (_) async => lifecycle,
          ),
          backgroundScheduleStatusRefreshSignalProvider.overrideWithValue(
            statusRefreshes,
          ),
          automaticSessionReauthenticationServiceProvider.overrideWith(
            (_) async => automatic,
          ),
          desktopDeadlineReminderDeliveryCoordinatorProvider.overrideWith(
            (_) async => deadlineDelivery,
          ),
        ],
        child: Leb2WatchApp(configuration: AppConfiguration.parse()),
      ),
    );
    sessions.add(
      const SessionLifecycleSnapshot(
        state: SessionLifecycleState.active,
        revision: 1,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(reconciler.executionAllowedValues, [isTrue]);
    expect(statusRefreshRequests, 1);

    sessions.add(
      const SessionLifecycleSnapshot(
        state: SessionLifecycleState.expired,
        revision: 7,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(reconciler.executionAllowedValues, [isTrue, isFalse]);
    expect(automatic.revisions, [7]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(sync.reasons, [SyncReason.appResume]);
    expect(statusRefreshRequests, 3);
    expect(deadlineStore.clearPermissionBlockedCalls, 1);
  });

  testWidgets('a newer active revision supersedes delayed expired work', (
    tester,
  ) async {
    final sessions = StreamController<SessionLifecycleSnapshot>();
    final reconciler = _AppBackgroundReconciler();
    final gate = Completer<void>();
    reconciler.nextGate = gate;
    final automatic = _AppAutomaticReauthenticationService();
    final setup = await _pumpLifecycleApp(
      tester,
      sessions: sessions,
      reconciler: reconciler,
      automatic: automatic,
    );
    addTearDown(setup.dispose);

    sessions.add(
      const SessionLifecycleSnapshot(
        state: SessionLifecycleState.expired,
        revision: 7,
      ),
    );
    await tester.pump();
    expect(reconciler.executionAllowedValues, [isFalse]);
    sessions.add(
      const SessionLifecycleSnapshot(
        state: SessionLifecycleState.active,
        revision: 8,
      ),
    );
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(reconciler.executionAllowedValues, [isFalse, isTrue]);
    expect(automatic.revisions, isEmpty);
  });

  testWidgets('delayed active work cannot suppress a later expiry', (
    tester,
  ) async {
    final sessions = StreamController<SessionLifecycleSnapshot>();
    final reconciler = _AppBackgroundReconciler();
    final gate = Completer<void>();
    reconciler.nextGate = gate;
    final automatic = _AppAutomaticReauthenticationService();
    final setup = await _pumpLifecycleApp(
      tester,
      sessions: sessions,
      reconciler: reconciler,
      automatic: automatic,
    );
    addTearDown(setup.dispose);

    sessions.add(
      const SessionLifecycleSnapshot(
        state: SessionLifecycleState.active,
        revision: 7,
      ),
    );
    await tester.pump();
    sessions.add(
      const SessionLifecycleSnapshot(
        state: SessionLifecycleState.expired,
        revision: 7,
      ),
    );
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(reconciler.executionAllowedValues, [isTrue, isFalse]);
    expect(automatic.revisions, [7]);
  });

  testWidgets('duplicate persisted expiry triggers foreground recovery once', (
    tester,
  ) async {
    final sessions = StreamController<SessionLifecycleSnapshot>();
    final reconciler = _AppBackgroundReconciler();
    final automatic = _AppAutomaticReauthenticationService();
    final setup = await _pumpLifecycleApp(
      tester,
      sessions: sessions,
      reconciler: reconciler,
      automatic: automatic,
    );
    addTearDown(setup.dispose);
    const expired = SessionLifecycleSnapshot(
      state: SessionLifecycleState.expired,
      revision: 7,
    );

    sessions
      ..add(expired)
      ..add(expired);
    await tester.pumpAndSettle();

    expect(reconciler.executionAllowedValues, [isFalse]);
    expect(automatic.revisions, [7]);
  });
}

Future<_LifecycleAppSetup> _pumpLifecycleApp(
  WidgetTester tester, {
  required StreamController<SessionLifecycleSnapshot> sessions,
  required _AppBackgroundReconciler reconciler,
  required _AppAutomaticReauthenticationService automatic,
}) async {
  final flow = AppFlowController();
  final notifications = _AppNotificationService();
  final refresh = BackgroundScheduleStatusRefreshSignal();
  final lifecycle = BackgroundMonitoringLifecycle(
    reconciler,
    BackgroundSyncRunner(const _AppBackgroundTargetStore(), _AppSyncService()),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appFlowControllerProvider.overrideWithValue(flow),
        localNotificationServiceProvider.overrideWithValue(notifications),
        newAssignmentNotificationDrainProvider.overrideWith(
          (_) async => _AppNotificationDrain(),
        ),
        sessionLifecycleProvider.overrideWith((_) => sessions.stream),
        backgroundMonitoringLifecycleProvider.overrideWith(
          (_) async => lifecycle,
        ),
        backgroundScheduleStatusRefreshSignalProvider.overrideWithValue(
          refresh,
        ),
        automaticSessionReauthenticationServiceProvider.overrideWith(
          (_) async => automatic,
        ),
        desktopDeadlineReminderDeliveryCoordinatorProvider.overrideWith(
          (_) async => null,
        ),
      ],
      child: Leb2WatchApp(configuration: AppConfiguration.parse()),
    ),
  );
  await tester.pump();
  return _LifecycleAppSetup(flow, notifications, refresh, sessions);
}

final class _LifecycleAppSetup {
  const _LifecycleAppSetup(
    this.flow,
    this.notifications,
    this.refresh,
    this.sessions,
  );

  final AppFlowController flow;
  final _AppNotificationService notifications;
  final BackgroundScheduleStatusRefreshSignal refresh;
  final StreamController<SessionLifecycleSnapshot> sessions;

  Future<void> dispose() async {
    flow.dispose();
    notifications.dispose();
    refresh.dispose();
    await sessions.close();
  }
}

final class _AppAutomaticReauthenticationService
    implements AutomaticSessionReauthenticationService {
  final revisions = <int>[];

  @override
  Future<void> cancelCurrent() async {}

  @override
  Future<AutomaticSessionReauthenticationResult> reauthenticate({
    required int expectedExpiredRevision,
    AutomaticSessionReauthenticationCancellation? cancellation,
  }) async {
    revisions.add(expectedExpiredRevision);
    return const AutomaticSessionReauthenticationFailed(
      AutomaticReauthenticationFailureKind.notEnabled,
    );
  }
}

final class _AppNotificationDrain implements NewAssignmentNotificationDrain {
  int calls = 0;

  @override
  Future<void> drainActiveCached() async {
    calls += 1;
  }
}

final class _AppDeadlineDeliveryStore
    implements DesktopDeadlineReminderDeliveryStore {
  int clearPermissionBlockedCalls = 0;

  @override
  Future<void> clearPermissionBlocked() async {
    clearPermissionBlockedCalls += 1;
  }

  @override
  Future<DeadlineReminderDeliveryClaim?> claimNext({
    required String ownerToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async => null;

  @override
  Future<bool> heartbeat({
    required DeadlineReminderDeliveryClaim claim,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async => false;

  @override
  Future<bool> markSubmitted({
    required DeadlineReminderDeliveryClaim claim,
    required DateTime recordedAtUtc,
  }) async => false;

  @override
  Future<bool> markSuppressed({
    required DeadlineReminderDeliveryClaim claim,
    required DeadlineReminderDeliverySuppression suppression,
    required DateTime recordedAtUtc,
  }) async => false;

  @override
  Future<DateTime?> readNextWakeAtUtc() async => null;

  @override
  Future<bool> releasePending({
    required DeadlineReminderDeliveryClaim claim,
    required DeadlineReminderDeliveryRetryFailure failure,
  }) async => false;

  @override
  Stream<void> watchQueueChanges() => const Stream.empty();
}

final class _AppNotificationService implements LocalNotificationService {
  _AppNotificationService({this.launchTarget});

  final LocalNotificationTarget? launchTarget;
  final StreamController<LocalNotificationTarget> _responses =
      StreamController<LocalNotificationTarget>.broadcast(sync: true);
  int initializeCalls = 0;
  bool _disposed = false;

  void emit(LocalNotificationTarget target) {
    if (!_disposed) {
      _responses.add(target);
    }
  }

  @override
  Stream<LocalNotificationTarget> get responses => _responses.stream;

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancelReminder(LocalNotificationId id) async {}

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_responses.close());
  }

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    final target = launchTarget;
    if (target != null) {
      emit(target);
    }
  }

  @override
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission() async =>
      NotificationDeliveryPermissionStatus.allowed;

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.notRequired;

  @override
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showDueDeadlineReminder(
    DeadlineReminderNotification request,
  ) async {}

  @override
  Future<void> showNewAssignment(NewAssignmentNotification request) async {}

  @override
  Future<void> showTestNotification() async {}
}

final class _AppAssignmentDashboardService
    implements AssignmentDashboardService {
  final AssignmentDashboardCache _cache = AssignmentDashboardCache(
    activeSemesterId: 101,
    session: const SessionLifecycleSnapshot(
      state: SessionLifecycleState.active,
      revision: 1,
    ),
    courses: const [],
    assignments: const [],
    latestAttempt: null,
    latestSuccess: null,
  );

  @override
  Future<AssignmentDashboardPreferences> readPreferences() async =>
      const AssignmentDashboardPreferences();

  @override
  Future<void> savePreferences(
    AssignmentDashboardPreferences preferences,
  ) async {}

  @override
  Future<AssignmentDashboardRefreshResult> refresh(SyncReason reason) async =>
      AssignmentDashboardRefreshSuccess(_cache.targetKey);

  @override
  Stream<AssignmentDashboardCache> watchCached() => Stream.value(_cache);
}

final class _AppAssignmentDetailService implements AssignmentDetailService {
  _AppAssignmentDetailService({this.events});

  final List<String>? events;
  final List<AssignmentDetailKey> keys = <AssignmentDetailKey>[];

  @override
  Stream<AssignmentDetailState> watch(AssignmentDetailKey key) {
    keys.add(key);
    events?.add('route:${key.identityKey}');
    return Stream.value(
      MissingAssignmentDetail(
        key: key,
        sync: const AssignmentDetailSyncEvidence(
          latestAttemptStatus: AssignmentDetailSyncStatus.success,
          latestAttemptFailureCategory: null,
          latestSuccessCompletedAtUtc: null,
        ),
      ),
    );
  }
}

final class _AppBackgroundReconciler implements BackgroundScheduleReconciler {
  final List<bool> executionAllowedValues = [];
  Completer<void>? nextGate;

  @override
  Future<void> reconcilePeriodicSync({required bool executionAllowed}) async {
    executionAllowedValues.add(executionAllowed);
    final gate = nextGate;
    nextGate = null;
    await gate?.future;
  }
}

final class _AppBackgroundTargetStore implements BackgroundSyncTargetStore {
  const _AppBackgroundTargetStore();

  @override
  Future<BackgroundSyncTargetPolicy> readPolicy() async {
    return const BackgroundSyncTargetPolicy(
      monitoringEnabled: true,
      semesterId: 101,
      userId: 2001,
      sessionState: SessionLifecycleState.active,
      backgroundMonitoredCourseCount: 1,
    );
  }
}

final class _AppSyncService implements AssignmentSyncService {
  final List<SyncReason> reasons = [];

  @override
  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  }) async {}

  @override
  Future<SyncBackoffStatus?> getBackoffStatus({
    required int semesterId,
    required int userId,
  }) async => null;

  @override
  Future<SyncOutcome> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) async {
    reasons.add(reason);
    final now = DateTime.utc(2026, 7, 26);
    return SyncSuccess(
      operationId: 1,
      semesterId: semesterId,
      reason: reason,
      startedAtUtc: now,
      completedAtUtc: now,
      courseCount: 1,
      activityCount: 1,
    );
  }
}
