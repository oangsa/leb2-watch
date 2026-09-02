import 'dart:async';

import 'package:leb2_watch/src/core/session/session_lifecycle.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_service.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/application/assignment_dashboard_preferences.dart';
import 'package:leb2_watch/src/features/assignments/dashboard/data/assignment_dashboard_store.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';

const dashboardActiveSession = SessionLifecycleSnapshot(
  state: SessionLifecycleState.active,
  revision: 4,
);

AssignmentDashboardCache dashboardCache({
  int? semesterId = 101,
  SessionLifecycleSnapshot session = dashboardActiveSession,
  List<AssignmentDashboardCourse>? courses,
  List<CachedAssignment>? assignments,
  AssignmentDashboardSyncRun? latestAttempt,
  AssignmentDashboardSyncRun? latestSuccess,
}) {
  final success =
      latestSuccess ??
      AssignmentDashboardSyncRun(
        outcome: AssignmentDashboardSyncOutcome.success,
        startedAtUtc: DateTime.utc(2026, 7, 26, 8),
        completedAtUtc: DateTime.utc(2026, 7, 26, 8, 1),
        failureCategory: null,
      );
  return AssignmentDashboardCache(
    activeSemesterId: semesterId,
    session: session,
    courses:
        courses ??
        const [
          AssignmentDashboardCourse(id: 3001, name: 'Algorithms'),
          AssignmentDashboardCourse(id: 3002, name: 'Networks'),
        ],
    assignments:
        assignments ??
        [
          dashboardAssignment(
            identityKey: 'backend:1001',
            title: 'Graph traversal',
            dueDateSource: '2026-08-01T16:30:00+07:00',
          ),
          dashboardAssignment(
            identityKey: 'backend:1002',
            title: 'Packet analysis',
            courseId: 3002,
            courseName: 'Networks',
            dueDateSource: '2026-08-03T09:00:00',
            isBaseline: false,
            firstSeenAtUtc: DateTime.utc(2026, 7, 26, 9),
          ),
        ],
    latestAttempt: latestAttempt ?? success,
    latestSuccess: latestSuccess ?? success,
  );
}

CachedAssignment dashboardAssignment({
  required String identityKey,
  String title = 'Assignment',
  int courseId = 3001,
  String courseName = 'Algorithms',
  String activityType = 'ASM',
  String? dueDateSource = '2026-08-01T12:00:00Z',
  bool dueDateExceed = false,
  AssignmentSubmissionStatus submissionStatus =
      AssignmentSubmissionStatus.unsubmitted,
  bool backendReportedStarred = false,
  DateTime? firstSeenAtUtc,
  bool isBaseline = true,
}) {
  return CachedAssignment(
    semesterId: 101,
    identityKey: identityKey,
    courseId: courseId,
    courseName: courseName,
    title: title,
    activityType: activityType,
    dueDateSource: dueDateSource,
    dueDateExceed: dueDateExceed,
    submissionStatus: submissionStatus,
    backendReportedStarred: backendReportedStarred,
    firstSeenAtUtc: firstSeenAtUtc ?? DateTime.utc(2026, 7, 25),
    isBaseline: isBaseline,
  );
}

final class FakeAssignmentDashboardService
    implements AssignmentDashboardService {
  FakeAssignmentDashboardService({
    AssignmentDashboardCache? initialCache,
    this.initialPreferences = const AssignmentDashboardPreferences(),
    this.refreshResult,
    this.refreshGate,
  }) : initialCache = initialCache ?? dashboardCache();

  AssignmentDashboardCache initialCache;
  AssignmentDashboardPreferences initialPreferences;
  AssignmentDashboardRefreshResult? refreshResult;
  Completer<AssignmentDashboardRefreshResult>? refreshGate;
  final controller = StreamController<AssignmentDashboardCache>.broadcast();
  final List<SyncReason> reasons = [];
  final List<AssignmentDashboardPreferences> preferenceSaveAttempts = [];
  final List<AssignmentDashboardPreferences> savedPreferences = [];
  final List<Completer<void>> preferenceSaveGates = [];
  bool failPreferenceRead = false;
  bool failPreferenceWrite = false;

  int get refreshCalls => reasons.length;

  @override
  Future<AssignmentDashboardPreferences> readPreferences() async {
    if (failPreferenceRead) {
      throw StateError('<PRIVATE_PREFERENCE_READ_ERROR>');
    }
    return initialPreferences;
  }

  @override
  Future<void> savePreferences(
    AssignmentDashboardPreferences preferences,
  ) async {
    preferenceSaveAttempts.add(preferences);
    if (preferenceSaveGates.isNotEmpty) {
      await preferenceSaveGates.removeAt(0).future;
    }
    if (failPreferenceWrite) {
      throw StateError('<PRIVATE_PREFERENCE_WRITE_ERROR>');
    }
    savedPreferences.add(preferences);
    initialPreferences = preferences;
  }

  @override
  Future<AssignmentDashboardRefreshResult> refresh(SyncReason reason) async {
    reasons.add(reason);
    final gate = refreshGate;
    if (gate != null) {
      return gate.future;
    }
    return refreshResult ??
        AssignmentDashboardRefreshSuccess(initialCache.targetKey);
  }

  @override
  Stream<AssignmentDashboardCache> watchCached() async* {
    yield initialCache;
    yield* controller.stream;
  }

  Future<void> close() => controller.close();
}
