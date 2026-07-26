import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
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
