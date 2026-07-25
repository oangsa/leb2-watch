import 'package:leb2_watch/src/core/network/domain/sync_failure.dart';

enum SyncReason {
  initialSetup,
  appLaunch,
  appResume,
  manualRefresh,
  backgroundTask,
  desktopTimer,
  trayAction,
}

abstract interface class AssignmentSyncService {
  Future<SyncResult> synchronize({
    required int semesterId,
    required int userId,
    required SyncReason reason,
  });

  Future<void> cancelCurrent({required int semesterId, required int userId});
}

sealed class SyncResult {
  const SyncResult({
    required this.operationId,
    required this.semesterId,
    required this.reason,
    required this.startedAtUtc,
    required this.completedAtUtc,
  });

  final int operationId;
  final int semesterId;
  final SyncReason reason;
  final DateTime startedAtUtc;
  final DateTime completedAtUtc;

  Object? get resultEqualityKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncResult &&
          other.runtimeType == runtimeType &&
          other.operationId == operationId &&
          other.semesterId == semesterId &&
          other.reason == reason &&
          other.startedAtUtc == startedAtUtc &&
          other.completedAtUtc == completedAtUtc &&
          other.resultEqualityKey == resultEqualityKey;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    operationId,
    semesterId,
    reason,
    startedAtUtc,
    completedAtUtc,
    resultEqualityKey,
  );

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class SyncSuccess extends SyncResult {
  const SyncSuccess({
    required super.operationId,
    required super.semesterId,
    required super.reason,
    required super.startedAtUtc,
    required super.completedAtUtc,
    required this.courseCount,
    required this.activityCount,
  });

  final int courseCount;
  final int activityCount;

  @override
  Object get resultEqualityKey => (courseCount, activityCount);
}

final class SyncFailed extends SyncResult {
  const SyncFailed({
    required super.operationId,
    required super.semesterId,
    required super.reason,
    required super.startedAtUtc,
    required super.completedAtUtc,
    required this.failure,
  });

  final SyncFailure failure;

  @override
  Object get resultEqualityKey => failure;
}

final class SyncCancelled extends SyncResult {
  const SyncCancelled({
    required super.operationId,
    required super.semesterId,
    required super.reason,
    required super.startedAtUtc,
    required super.completedAtUtc,
  });

  @override
  Object? get resultEqualityKey => null;
}
