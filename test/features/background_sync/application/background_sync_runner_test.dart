import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/authentication/application/automatic_session_reauthentication_service.dart';
import 'package:leb2_watch/src/features/authentication/application/reauthenticating_assignment_sync_service.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';
import 'package:leb2_watch/src/features/background_sync/application/background_sync_runner.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_schedule_store.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_sync_target_store.dart';

void main() {
  late AppDatabase database;
  late DriftBackgroundScheduleStore settings;
  late _SyncService sync;
  late BackgroundSyncRunner runner;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    settings = DriftBackgroundScheduleStore(
      database,
      jitterGenerator: (_) => 0,
    );
    sync = _SyncService();
    runner = BackgroundSyncRunner(
      DriftBackgroundSyncTargetStore(database),
      sync,
    );
  });

  tearDown(() => database.close());

  test('automatic runs skip before HTTP for every local policy gate', () async {
    expect(
      await runner.run(reason: SyncReason.backgroundTask),
      isA<BackgroundSyncDisabled>(),
    );
    expect(sync.requests, isEmpty);

    await settings.setMonitoringEnabled(true);
    expect(
      await runner.run(reason: SyncReason.backgroundTask),
      isA<BackgroundSyncMissingTarget>(),
    );
    await _seedTarget(database, session: 'expired');
    expect(
      await runner.run(reason: SyncReason.backgroundTask),
      isA<BackgroundSyncSessionPaused>(),
    );
    await database.customStatement(
      "UPDATE app_settings SET session_lifecycle = 'active'",
    );
    expect(
      await runner.run(reason: SyncReason.backgroundTask),
      isA<BackgroundSyncNoBackgroundCourses>(),
    );
    expect(sync.requests, isEmpty);
  });

  test(
    'tray action remains available while periodic monitoring is off',
    () async {
      await _seedTarget(database, session: 'active');
      sync.outcome = _success(SyncReason.trayAction);

      final result = await runner.run(reason: SyncReason.trayAction);

      expect(result, isA<BackgroundSyncSucceeded>());
      expect(sync.requests, [(101, 2001, SyncReason.trayAction)]);
    },
  );

  test('cancellation requests the existing target operation', () async {
    await _seedTarget(database, session: 'active', withCourse: true);
    await settings.setMonitoringEnabled(true);
    final pending = Completer<SyncOutcome>();
    sync.pending = pending;
    final cancellation = BackgroundSyncCancellationController();

    final running = runner.run(
      reason: SyncReason.backgroundTask,
      cancellation: cancellation,
    );
    await sync.started.future;
    cancellation.cancel();

    expect(await running, isA<BackgroundSyncCancelled>());
    expect(sync.cancelledTargets, [(101, 2001)]);
    pending.complete(_cancelled(SyncReason.backgroundTask));
  });

  test(
    'compatibility and device-binding failures do not schedule retries',
    () async {
      await _seedTarget(database, session: 'active', withCourse: true);
      await settings.setMonitoringEnabled(true);
      sync.outcome = SyncFailed(
        operationId: 1,
        semesterId: 101,
        reason: SyncReason.backgroundTask,
        startedAtUtc: DateTime.utc(2026, 7, 26),
        completedAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
        failure: const ClientCompatibilityFailure(
          ClientCompatibilityFailureReason.updateRequired,
        ),
      );

      final result = await runner.run(reason: SyncReason.backgroundTask);

      expect(result, isA<BackgroundSyncTerminalFailure>());
      expect((result as BackgroundSyncTerminalFailure).retryEligible, isFalse);
    },
  );

  test('headless recovery continues once and reports succeeded', () async {
    await _seedTarget(database, session: 'active', withCourse: true);
    await settings.setMonitoringEnabled(true);
    final continuation = _success(SyncReason.backgroundTask);
    final delegate = _SequenceSyncService([_expired(), continuation]);
    final automatic = _AutomaticService(
      const AutomaticSessionReauthenticationRecovered(),
    );
    final wrapped = ReauthenticatingAssignmentSyncService(
      delegate,
      automatic,
      _LifecycleStore(expired: true),
    );
    final recoveryRunner = BackgroundSyncRunner(
      DriftBackgroundSyncTargetStore(database),
      wrapped,
    );

    expect(
      await recoveryRunner.run(reason: SyncReason.backgroundTask),
      isA<BackgroundSyncSucceeded>(),
    );
    expect(delegate.requests, hasLength(2));
    expect(automatic.requests, [7]);
  });

  test(
    'headless secure-store failure pauses without a second request',
    () async {
      await _seedTarget(database, session: 'active', withCourse: true);
      await settings.setMonitoringEnabled(true);
      final delegate = _SequenceSyncService([_expired()]);
      final automatic = _AutomaticService(
        const AutomaticSessionReauthenticationFailed(
          AutomaticReauthenticationFailureKind.secureStorageUnavailable,
        ),
      );
      final wrapped = ReauthenticatingAssignmentSyncService(
        delegate,
        automatic,
        _LifecycleStore(expired: true),
      );
      final recoveryRunner = BackgroundSyncRunner(
        DriftBackgroundSyncTargetStore(database),
        wrapped,
      );

      expect(
        await recoveryRunner.run(reason: SyncReason.backgroundTask),
        isA<BackgroundSyncSessionPaused>(),
      );
      expect(delegate.requests, hasLength(1));
      expect(automatic.requests, [7]);
    },
  );
}

Future<void> _seedTarget(
  AppDatabase database, {
  required String session,
  bool withCourse = false,
}) async {
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: const Value(101)));
  await database
      .into(database.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          singletonId: const Value(1),
          activeSemesterId: const Value(101),
          leb2UserId: const Value(2001),
          sessionLifecycle: Value(session),
        ),
      );
  if (withCourse) {
    await database
        .into(database.courses)
        .insert(
          CoursesCompanion.insert(
            semesterId: 101,
            courseId: 3001,
            name: 'Course 3001',
          ),
        );
  }
}

SyncSuccess _success(SyncReason reason) => SyncSuccess(
  operationId: 1,
  semesterId: 101,
  reason: reason,
  startedAtUtc: DateTime.utc(2026, 7, 26),
  completedAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
  courseCount: 1,
  activityCount: 1,
);

SyncCancelled _cancelled(SyncReason reason) => SyncCancelled(
  operationId: 1,
  semesterId: 101,
  reason: reason,
  startedAtUtc: DateTime.utc(2026, 7, 26),
  completedAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
);

SyncFailed _expired() => SyncFailed(
  operationId: 1,
  semesterId: 101,
  reason: SyncReason.backgroundTask,
  startedAtUtc: DateTime.utc(2026, 7, 26),
  completedAtUtc: DateTime.utc(2026, 7, 26, 0, 1),
  failure: const SessionExpiredFailure(),
);

final class _SyncService implements AssignmentSyncService {
  final List<(int, int, SyncReason)> requests = [];
  final List<(int, int)> cancelledTargets = [];
  final Completer<void> started = Completer<void>();
  SyncOutcome outcome = _success(SyncReason.backgroundTask);
  Completer<SyncOutcome>? pending;

  @override
  Future<SyncOutcome> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  }) {
    requests.add((semesterId, userId, reason));
    if (!started.isCompleted) {
      started.complete();
    }
    return pending?.future ?? Future.value(outcome);
  }

  @override
  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  }) async {
    cancelledTargets.add((semesterId, userId));
  }

  @override
  Future<SyncBackoffStatus?> getBackoffStatus({
    required int semesterId,
    required int userId,
  }) async {
    return null;
  }
}

final class _SequenceSyncService implements AssignmentSyncService {
  _SequenceSyncService(this.outcomes);

  final List<SyncOutcome> outcomes;
  final requests = <(int, int, SyncReason)>[];

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
    requests.add((semesterId, userId, reason));
    return outcomes.removeAt(0);
  }
}

final class _AutomaticService
    implements AutomaticSessionReauthenticationService {
  _AutomaticService(this.result);

  final AutomaticSessionReauthenticationResult result;
  final requests = <int>[];

  @override
  Future<void> cancelCurrent() async {}

  @override
  Future<AutomaticSessionReauthenticationResult> reauthenticate({
    required int expectedExpiredRevision,
    AutomaticSessionReauthenticationCancellation? cancellation,
  }) async {
    requests.add(expectedExpiredRevision);
    return result;
  }
}

final class _LifecycleStore implements SessionLifecycleStore {
  _LifecycleStore({required bool expired})
    : snapshot = SessionLifecycleSnapshot(
        state: expired
            ? SessionLifecycleState.expired
            : SessionLifecycleState.active,
        revision: 7,
      );

  final SessionLifecycleSnapshot snapshot;

  @override
  Future<bool> markExpired({required int expectedRevision}) async => false;

  @override
  Future<SessionLifecycleSnapshot> markVerifiedActive({
    required int userId,
  }) async => snapshot;

  @override
  Future<SessionLifecycleSnapshot?> markVerifiedActiveIfCurrent({
    required SessionLifecycleSnapshot expected,
    required int userId,
  }) async => snapshot == expected ? snapshot : null;

  @override
  Future<SessionLifecycleSnapshot> read() async => snapshot;

  @override
  Stream<SessionLifecycleSnapshot> watch() => Stream.value(snapshot);
}
