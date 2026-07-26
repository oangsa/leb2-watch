import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/local_database_access_gate.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';
import 'package:leb2_watch/src/features/assignments/sync/quiescence_aware_assignment_sync_service.dart';

void main() {
  late Directory temporaryDirectory;
  late LocalDatabaseStorage storage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'leb2-watch-sync-quiescence-',
    );
    storage = LocalDatabaseStorage(
      applicationSupportDirectoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('deletion cancels and joins an admitted synchronization', () async {
    final delegate = _BlockingSyncService();
    final service = QuiescenceAwareAssignmentSyncService(delegate, storage);

    var syncSettled = false;
    final sync = service
        .synchronize(
          semesterId: 101,
          userId: 2001,
          reason: SyncReason.manualRefresh,
        )
        .whenComplete(() => syncSettled = true);
    await delegate.started.future;

    final gate = await storage.beginDeletion();
    await delegate.cancellationRequested.future.timeout(
      const Duration(seconds: 1),
    );
    expect(syncSettled, isFalse);

    await expectLater(
      service.synchronize(
        semesterId: 101,
        userId: 2001,
        reason: SyncReason.manualRefresh,
      ),
      throwsA(
        isA<LocalDatabaseAccessException>().having(
          (error) => error.reason,
          'reason',
          LocalDatabaseAccessFailureReason.deletionInProgress,
        ),
      ),
    );
    expect(delegate.synchronizeCalls, 1);

    delegate.complete();
    expect(await sync, isA<SyncCancelled>());
    await gate.waitForActivityQuiescence();
    await gate.release();
  });
}

final class _BlockingSyncService implements AssignmentSyncService {
  final Completer<void> started = Completer<void>();
  final Completer<void> cancellationRequested = Completer<void>();
  final Completer<SyncOutcome> _outcome = Completer<SyncOutcome>();
  int synchronizeCalls = 0;

  void complete() {
    final now = DateTime.utc(2026, 7, 26);
    _outcome.complete(
      SyncCancelled(
        operationId: 1,
        semesterId: 101,
        reason: SyncReason.manualRefresh,
        startedAtUtc: now,
        completedAtUtc: now,
      ),
    );
  }

  @override
  Future<void> cancelCurrent({
    required int semesterId,
    required int userId,
  }) async {
    if (!cancellationRequested.isCompleted) {
      cancellationRequested.complete();
    }
  }

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
  }) {
    synchronizeCalls += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    return _outcome.future;
  }
}
