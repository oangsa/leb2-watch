import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart' hide CoursePreference;

const _maximumCourseIdentifier = 2147483647;

final class CourseKey {
  const CourseKey({required this.semesterId, required this.courseId});

  final int semesterId;
  final int courseId;

  @override
  bool operator ==(Object other) =>
      other is CourseKey &&
      other.semesterId == semesterId &&
      other.courseId == courseId;

  @override
  int get hashCode => Object.hash(semesterId, courseId);

  @override
  String toString() => 'CourseKey(redacted: true)';
}

final class CoursePreference {
  const CoursePreference({
    this.notificationsMuted = false,
    this.backgroundMonitoringEnabled = true,
  });

  final bool notificationsMuted;
  final bool backgroundMonitoringEnabled;

  @override
  bool operator ==(Object other) =>
      other is CoursePreference &&
      other.notificationsMuted == notificationsMuted &&
      other.backgroundMonitoringEnabled == backgroundMonitoringEnabled;

  @override
  int get hashCode =>
      Object.hash(notificationsMuted, backgroundMonitoringEnabled);

  @override
  String toString() => 'CoursePreference(redacted: true)';
}

final class CourseSummary {
  const CourseSummary({
    required this.key,
    required this.name,
    required this.postBaselineActivityCount,
    required this.notReportedExceededDeadlineCount,
    required this.preference,
  });

  final CourseKey key;
  final String name;
  final int postBaselineActivityCount;
  final int notReportedExceededDeadlineCount;
  final CoursePreference preference;

  @override
  String toString() => 'CourseSummary(redacted: true)';
}

final class ActiveCourseCatalog {
  ActiveCourseCatalog({
    required this.activeSemesterId,
    this.activeSemesterName,
    required Iterable<CourseSummary> courses,
  }) : courses = List<CourseSummary>.unmodifiable(courses);

  final int? activeSemesterId;
  final String? activeSemesterName;
  final List<CourseSummary> courses;

  bool get hasActiveSemester => activeSemesterId != null;
  bool get isEmpty => courses.isEmpty;

  @override
  String toString() => 'ActiveCourseCatalog(redacted: true)';
}

sealed class CoursePreferenceWriteResult {
  const CoursePreferenceWriteResult();
}

final class CoursePreferenceWriteApplied extends CoursePreferenceWriteResult {
  const CoursePreferenceWriteApplied();

  @override
  String toString() => 'CoursePreferenceWriteApplied(redacted: true)';
}

final class CoursePreferenceWriteStale extends CoursePreferenceWriteResult {
  const CoursePreferenceWriteStale();

  @override
  String toString() => 'CoursePreferenceWriteStale(redacted: true)';
}

enum CoursePreferencesStoreOperation {
  watchCatalog,
  readCatalog,
  writePreference,
  readPolicy,
  readBackgroundCourses,
}

final class CoursePreferencesStoreException implements Exception {
  const CoursePreferencesStoreException(this.operation);

  final CoursePreferencesStoreOperation operation;

  @override
  String toString() =>
      'CoursePreferencesStoreException('
      'operation: ${operation.name}, redacted: true)';
}

abstract interface class CoursePreferencesStore {
  Stream<ActiveCourseCatalog> watchActiveCatalog();

  Future<ActiveCourseCatalog> readActiveCatalog();

  Future<CoursePreferenceWriteResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  });

  Future<CoursePreferenceWriteResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  });

  Future<CoursePreference?> readCurrentCoursePreference(CourseKey key);

  Future<Set<CourseKey>> readBackgroundMonitoredCourses(int semesterId);
}

final class DriftCoursePreferencesStore implements CoursePreferencesStore {
  DriftCoursePreferencesStore(this._database);

  final AppDatabase _database;

  Selectable<TypedResult> get _catalogQuery {
    return (_database.select(_database.appSettings).join([
        leftOuterJoin(
          _database.semesters,
          _database.semesters.semesterId.equalsExp(
            _database.appSettings.activeSemesterId,
          ),
        ),
        leftOuterJoin(
          _database.courses,
          _database.courses.semesterId.equalsExp(
            _database.appSettings.activeSemesterId,
          ),
        ),
        leftOuterJoin(
          _database.activities,
          _database.activities.semesterId.equalsExp(
                _database.courses.semesterId,
              ) &
              _database.activities.courseId.equalsExp(
                _database.courses.courseId,
              ),
        ),
        leftOuterJoin(
          _database.seenActivities,
          _database.seenActivities.semesterId.equalsExp(
                _database.activities.semesterId,
              ) &
              _database.seenActivities.identityKey.equalsExp(
                _database.activities.identityKey,
              ),
        ),
        leftOuterJoin(
          _database.coursePreferences,
          _database.coursePreferences.semesterId.equalsExp(
                _database.courses.semesterId,
              ) &
              _database.coursePreferences.courseId.equalsExp(
                _database.courses.courseId,
              ),
        ),
      ])
      ..where(_database.appSettings.singletonId.equals(1))
      ..orderBy([
        OrderingTerm.asc(_database.courses.name),
        OrderingTerm.asc(_database.courses.courseId),
      ]));
  }

  @override
  Stream<ActiveCourseCatalog> watchActiveCatalog() {
    return _catalogQuery.watch().map(_decodeCatalog).handleError((
      Object _,
      StackTrace _,
    ) {
      throw const CoursePreferencesStoreException(
        CoursePreferencesStoreOperation.watchCatalog,
      );
    });
  }

  @override
  Future<ActiveCourseCatalog> readActiveCatalog() {
    return _run(
      CoursePreferencesStoreOperation.readCatalog,
      () async => _decodeCatalog(await _catalogQuery.get()),
    );
  }

  @override
  Future<CoursePreferenceWriteResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  }) {
    return _writePreference(
      key,
      update: (current) => CoursePreference(
        notificationsMuted: muted,
        backgroundMonitoringEnabled: current.backgroundMonitoringEnabled,
      ),
    );
  }

  @override
  Future<CoursePreferenceWriteResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  }) {
    return _writePreference(
      key,
      update: (current) => CoursePreference(
        notificationsMuted: current.notificationsMuted,
        backgroundMonitoringEnabled: enabled,
      ),
    );
  }

  @override
  Future<CoursePreference?> readCurrentCoursePreference(CourseKey key) {
    _validateKey(key);
    return _run(CoursePreferencesStoreOperation.readPolicy, () async {
      final row = await _database
          .customSelect(
            'SELECT COALESCE(p.notifications_muted, 0) '
            'AS notifications_muted, '
            'COALESCE(p.background_monitoring_enabled, 1) '
            'AS background_monitoring_enabled '
            'FROM courses AS c '
            'LEFT JOIN course_preferences AS p '
            'ON p.semester_id = c.semester_id '
            'AND p.course_id = c.course_id '
            'WHERE c.semester_id = ? AND c.course_id = ?',
            variables: [
              Variable<int>(key.semesterId),
              Variable<int>(key.courseId),
            ],
            readsFrom: {_database.courses, _database.coursePreferences},
          )
          .getSingleOrNull();
      if (row == null) {
        return null;
      }
      return CoursePreference(
        notificationsMuted: row.read<bool>('notifications_muted'),
        backgroundMonitoringEnabled: row.read<bool>(
          'background_monitoring_enabled',
        ),
      );
    });
  }

  @override
  Future<Set<CourseKey>> readBackgroundMonitoredCourses(int semesterId) {
    _validateIdentifier(semesterId, 'semesterId');
    return _run(
      CoursePreferencesStoreOperation.readBackgroundCourses,
      () async {
        final rows = await _database
            .customSelect(
              'SELECT c.course_id FROM courses AS c '
              'LEFT JOIN course_preferences AS p '
              'ON p.semester_id = c.semester_id '
              'AND p.course_id = c.course_id '
              'WHERE c.semester_id = ? '
              'AND COALESCE(p.background_monitoring_enabled, 1) = 1 '
              'ORDER BY c.course_id',
              variables: [Variable<int>(semesterId)],
              readsFrom: {_database.courses, _database.coursePreferences},
            )
            .get();
        return Set<CourseKey>.unmodifiable(
          rows.map(
            (row) => CourseKey(
              semesterId: semesterId,
              courseId: row.read<int>('course_id'),
            ),
          ),
        );
      },
    );
  }

  Future<CoursePreferenceWriteResult> _writePreference(
    CourseKey key, {
    required CoursePreference Function(CoursePreference current) update,
  }) {
    _validateKey(key);
    return _run(
      CoursePreferencesStoreOperation.writePreference,
      () => _database.transaction(() async {
        final activeSemester =
            await (_database.selectOnly(_database.appSettings)
                  ..addColumns([_database.appSettings.activeSemesterId]))
                .getSingleOrNull();
        if (activeSemester?.read(_database.appSettings.activeSemesterId) !=
            key.semesterId) {
          return const CoursePreferenceWriteStale();
        }

        final currentCourse =
            await (_database.selectOnly(_database.courses)
                  ..addColumns([_database.courses.courseId])
                  ..where(
                    Expression.and([
                      _database.courses.semesterId.equals(key.semesterId),
                      _database.courses.courseId.equals(key.courseId),
                    ]),
                  ))
                .getSingleOrNull();
        if (currentCourse == null) {
          return const CoursePreferenceWriteStale();
        }

        final stored =
            await (_database.select(_database.coursePreferences)..where(
                  (row) => Expression.and([
                    row.semesterId.equals(key.semesterId),
                    row.courseId.equals(key.courseId),
                  ]),
                ))
                .getSingleOrNull();
        final current = stored == null
            ? const CoursePreference()
            : CoursePreference(
                notificationsMuted: stored.notificationsMuted,
                backgroundMonitoringEnabled: stored.backgroundMonitoringEnabled,
              );
        final next = update(current);

        await _database
            .into(_database.coursePreferences)
            .insertOnConflictUpdate(
              CoursePreferencesCompanion.insert(
                semesterId: key.semesterId,
                courseId: key.courseId,
                notificationsMuted: Value(next.notificationsMuted),
                backgroundMonitoringEnabled: Value(
                  next.backgroundMonitoringEnabled,
                ),
              ),
            );
        return const CoursePreferenceWriteApplied();
      }),
    );
  }

  ActiveCourseCatalog _decodeCatalog(List<TypedResult> rows) {
    final settings = rows.isEmpty
        ? null
        : rows.first.readTable(_database.appSettings);
    final activeSemesterId = settings?.activeSemesterId;
    final byCourse = <CourseKey, _CourseAccumulator>{};
    for (final row in rows) {
      final course = row.readTableOrNull(_database.courses);
      if (course == null || activeSemesterId == null) {
        continue;
      }
      final key = CourseKey(
        semesterId: activeSemesterId,
        courseId: course.courseId,
      );
      final storedPreference = row.readTableOrNull(_database.coursePreferences);
      final accumulator = byCourse.putIfAbsent(
        key,
        () => _CourseAccumulator(
          key: key,
          name: course.name,
          preference: storedPreference == null
              ? const CoursePreference()
              : CoursePreference(
                  notificationsMuted: storedPreference.notificationsMuted,
                  backgroundMonitoringEnabled:
                      storedPreference.backgroundMonitoringEnabled,
                ),
        ),
      );
      final activity = row.readTableOrNull(_database.activities);
      if (activity == null) {
        continue;
      }
      final seen = row.readTableOrNull(_database.seenActivities);
      if (seen != null && !seen.isBaseline) {
        accumulator.postBaselineActivityCount += 1;
      }
      if (activity.dueDateSource != null && !activity.dueDateExceed) {
        accumulator.notReportedExceededDeadlineCount += 1;
      }
    }
    final accumulators = byCourse.values.toList()
      ..sort((first, second) {
        final byName = first.name.toLowerCase().compareTo(
          second.name.toLowerCase(),
        );
        return byName != 0
            ? byName
            : first.key.courseId.compareTo(second.key.courseId);
      });
    return ActiveCourseCatalog(
      activeSemesterId: activeSemesterId,
      activeSemesterName: rows.isEmpty
          ? null
          : rows.first.readTableOrNull(_database.semesters)?.name,
      courses: accumulators
          .map(
            (course) => CourseSummary(
              key: course.key,
              name: course.name,
              postBaselineActivityCount: course.postBaselineActivityCount,
              notReportedExceededDeadlineCount:
                  course.notReportedExceededDeadlineCount,
              preference: course.preference,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<T> _run<T>(
    CoursePreferencesStoreOperation operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on ArgumentError {
      rethrow;
    } on Object {
      throw CoursePreferencesStoreException(operation);
    }
  }

  void _validateKey(CourseKey key) {
    _validateIdentifier(key.semesterId, 'semesterId');
    _validateIdentifier(key.courseId, 'courseId');
  }

  void _validateIdentifier(int value, String name) {
    if (value <= 0 || value > _maximumCourseIdentifier) {
      throw ArgumentError.value(value, name, 'Must be a positive int32.');
    }
  }

  @override
  String toString() => 'DriftCoursePreferencesStore(redacted: true)';
}

final class _CourseAccumulator {
  _CourseAccumulator({
    required this.key,
    required this.name,
    required this.preference,
  });

  final CourseKey key;
  final String name;
  final CoursePreference preference;
  int postBaselineActivityCount = 0;
  int notReportedExceededDeadlineCount = 0;
}
