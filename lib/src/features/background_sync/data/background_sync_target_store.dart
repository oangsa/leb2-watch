import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/session/session_lifecycle.dart';

final class BackgroundSyncTargetPolicy {
  const BackgroundSyncTargetPolicy({
    required this.monitoringEnabled,
    required this.semesterId,
    required this.userId,
    required this.sessionState,
    required this.backgroundMonitoredCourseCount,
  });

  final bool monitoringEnabled;
  final int? semesterId;
  final int? userId;
  final SessionLifecycleState sessionState;
  final int backgroundMonitoredCourseCount;

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
                'AND COALESCE(p.background_monitoring_enabled, 1) = 1',
                variables: [Variable<int>(semesterId)],
                readsFrom: {_database.courses, _database.coursePreferences},
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
        );
      });
    } on Object {
      throw const BackgroundSyncTargetStoreException();
    }
  }

  @override
  String toString() => 'DriftBackgroundSyncTargetStore(redacted: true)';
}
