import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/session/session_lifecycle.dart';
import '../domain/background_scheduler.dart';

final class BackgroundSyncTargetPolicy {
  const BackgroundSyncTargetPolicy({
    required this.monitoringEnabled,
    required this.semesterId,
    required this.userId,
    required this.sessionState,
    required this.backgroundMonitoredCourseCount,
    this.daytimeCadence = defaultBackgroundFetchCadence,
    this.lastSuccessfulSyncAtUtc,
  });

  final bool monitoringEnabled;
  final int? semesterId;
  final int? userId;
  final SessionLifecycleState sessionState;
  final int backgroundMonitoredCourseCount;
  final BackgroundFetchCadence daytimeCadence;

  /// When the most recent successful synchronization of [semesterId] finished,
  /// so a scheduled run can tell that another path already did its work.
  final DateTime? lastSuccessfulSyncAtUtc;

  bool get hasTarget => semesterId != null && userId != null;
  bool get hasBackgroundMonitoredCourse => backgroundMonitoredCourseCount > 0;

  @override
  String toString() => 'BackgroundSyncTargetPolicy(redacted: true)';
}

abstract interface class BackgroundSyncTargetStore {
  Future<BackgroundSyncTargetPolicy> readPolicy();
}

final class BackgroundSyncTargetStoreException implements Exception {
  const BackgroundSyncTargetStoreException();

  @override
  String toString() => 'BackgroundSyncTargetStoreException(redacted: true)';
}

final class DriftBackgroundSyncTargetStore
    implements BackgroundSyncTargetStore {
  const DriftBackgroundSyncTargetStore(this._database);

  final AppDatabase _database;

  @override
  Future<BackgroundSyncTargetPolicy> readPolicy() async {
    try {
      return await _database.transaction(() async {
        final background = await _database
            .select(_database.backgroundScheduleSettings)
            .getSingle();
        final appSettings = await _database
            .select(_database.appSettings)
            .getSingleOrNull();
        final session = decodeStoredSessionLifecycle(appSettings);
        final semesterId = appSettings?.activeSemesterId;
        var monitoredCourseCount = 0;
        if (semesterId != null) {
          final countRow = await _database
              .customSelect(
                'SELECT COUNT(*) AS monitored_count '
                'FROM courses AS c '
                'LEFT JOIN course_preferences AS p '
                'ON p.semester_id = c.semester_id '
                'AND p.course_id = c.course_id '
                'WHERE c.semester_id = ? '
                'AND COALESCE((SELECT course_background_monitoring_enabled '
                'FROM app_settings WHERE singleton_id = 1), 1) = 1 '
                'AND COALESCE(p.background_monitoring_enabled, 1) = 1',
                variables: [Variable<int>(semesterId)],
                readsFrom: {
                  _database.appSettings,
                  _database.courses,
                  _database.coursePreferences,
                },
              )
              .getSingle();
          monitoredCourseCount = countRow.read<int>('monitored_count');
        }
        return BackgroundSyncTargetPolicy(
          monitoringEnabled: background.monitoringEnabled,
          semesterId: semesterId,
          userId: appSettings?.leb2UserId,
          sessionState: session.state,
          backgroundMonitoredCourseCount: monitoredCourseCount,
          daytimeCadence:
              BackgroundFetchCadence.fromMinutes(
                background.daytimeCadenceMinutes,
              ) ??
              defaultBackgroundFetchCadence,
          lastSuccessfulSyncAtUtc: semesterId == null
              ? null
              : await _readLastSuccessfulSyncAtUtc(semesterId),
        );
      });
    } on Object {
      throw const BackgroundSyncTargetStoreException();
    }
  }

  Future<DateTime?> _readLastSuccessfulSyncAtUtc(int semesterId) async {
    final row =
        await (_database.select(_database.syncRuns)
              ..where(
                (row) =>
                    row.semesterId.equals(semesterId) &
                    row.outcome.equals('success') &
                    row.completedAtUtc.isNotNull(),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.completedAtUtc)])
              ..limit(1))
            .getSingleOrNull();
    return row?.completedAtUtc;
  }

  @override
  String toString() => 'DriftBackgroundSyncTargetStore(redacted: true)';
}
