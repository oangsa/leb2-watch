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

enum AssignmentChangeKind { newActivity, deadlineChanged, removed }

final class AssignmentChange {
  const AssignmentChange({required this.identityKey, required this.kind});

  final String identityKey;
  final AssignmentChangeKind kind;

  @override
  bool operator ==(Object other) =>
      other is AssignmentChange &&
      other.identityKey == identityKey &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(identityKey, kind);

  @override
  String toString() => 'AssignmentChange(redacted: true)';
}

final class AssignmentChangeBatch {
  factory AssignmentChangeBatch(Iterable<AssignmentChange> changes) {
    final sorted = changes.toList()
      ..sort((left, right) {
        final kindOrder = left.kind.index.compareTo(right.kind.index);
        return kindOrder != 0
            ? kindOrder
            : left.identityKey.compareTo(right.identityKey);
      });
    return AssignmentChangeBatch._(List.unmodifiable(sorted));
  }

  const AssignmentChangeBatch._(this.changes);

  static const empty = AssignmentChangeBatch._(<AssignmentChange>[]);

  final List<AssignmentChange> changes;

  int count(AssignmentChangeKind kind) =>
      changes.where((change) => change.kind == kind).length;

  @override
  bool operator ==(Object other) {
    if (other is! AssignmentChangeBatch ||
        other.changes.length != changes.length) {
      return false;
    }
    for (var index = 0; index < changes.length; index++) {
      if (changes[index] != other.changes[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(changes);

  @override
  String toString() => 'AssignmentChangeBatch(redacted: true)';
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
    this.changes = AssignmentChangeBatch.empty,
  });

  final int courseCount;
  final int activityCount;
  final AssignmentChangeBatch changes;

  @override
  Object get resultEqualityKey => (courseCount, activityCount, changes);
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
