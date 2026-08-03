import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart'
    hide CoursePreference;
import 'package:leb2_watch/src/features/courses/data/course_preferences_store.dart';

void main() {
  late AppDatabase database;
  late DriftCoursePreferencesStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftCoursePreferencesStore(database);
  });

  tearDown(() => database.close());

  test('returns no-active and active-empty offline catalog states', () async {
    var catalog = await store.readActiveCatalog();
    expect(catalog.activeSemesterId, isNull);
    expect(catalog.courses, isEmpty);

    await _insertSemester(database, 101, active: true);
    catalog = await store.readActiveCatalog();

    expect(catalog.activeSemesterId, 101);
    expect(catalog.courses, isEmpty);
    expect(catalog.toString(), 'ActiveCourseCatalog(redacted: true)');
  });

  test('orders cached courses and projects documented defaults', () async {
    await _insertSemester(database, 101, active: true);
    await _insertCourse(database, 101, 3003, 'zeta');
    await _insertCourse(database, 101, 3002, 'Alpha');
    await _insertCourse(database, 101, 3001, 'alpha');

    final catalog = await store.readActiveCatalog();

    expect(catalog.courses.map((course) => course.key.courseId), [
      3001,
      3002,
      3003,
    ]);
    expect(
      catalog.courses.map((course) => course.preference),
      everyElement(const CoursePreference()),
    );
    expect(catalog.courses.first.toString(), 'CourseSummary(redacted: true)');
    expect(catalog.courses.first.key.toString(), 'CourseKey(redacted: true)');
    expect(
      catalog.courses.first.preference.toString(),
      'CoursePreference(redacted: true)',
    );
    expect(
      () => catalog.courses.add(catalog.courses.first),
      throwsUnsupportedError,
    );
  });

  test(
    'counts only current post-baseline activities and saved due evidence',
    () async {
      await _insertSemester(database, 101, active: true);
      await _insertCourse(database, 101, 3001, 'Course A');
      await _insertCourse(database, 101, 3002, 'Course B');

      await _insertActivity(
        database,
        key: 'baseline',
        courseId: 3001,
        dueDate: '2026-08-01T12:00:00',
        dueDateExceed: false,
        isBaseline: true,
      );
      await _insertActivity(
        database,
        key: 'new-unzoned',
        courseId: 3001,
        dueDate: '2026-08-02T12:00:00',
        dueDateExceed: false,
        isBaseline: false,
        submittedJson: '{"date":"submitted-looking"}',
      );
      await _insertActivity(
        database,
        key: 'new-zoned-overdue',
        courseId: 3001,
        dueDate: '2026-08-03T12:00:00+07:00',
        dueDateExceed: true,
        isBaseline: false,
      );
      await _insertActivity(
        database,
        key: 'new-no-deadline',
        courseId: 3001,
        dueDate: null,
        dueDateExceed: false,
        isBaseline: false,
      );
      await _insertSeenOnly(
        database,
        key: 'removed',
        courseId: 3001,
        isBaseline: false,
      );

      var catalog = await store.readActiveCatalog();
      var courseA = catalog.courses.first;
      expect(courseA.postBaselineActivityCount, 3);
      expect(courseA.notReportedExceededDeadlineCount, 2);

      await database.customStatement(
        "UPDATE activities SET course_id = 3002 WHERE identity_key = 'new-unzoned'",
      );
      catalog = await store.readActiveCatalog();
      courseA = catalog.courses.firstWhere(
        (course) => course.key.courseId == 3001,
      );
      final courseB = catalog.courses.firstWhere(
        (course) => course.key.courseId == 3002,
      );
      expect(courseA.postBaselineActivityCount, 2);
      expect(courseA.notReportedExceededDeadlineCount, 1);
      expect(courseB.postBaselineActivityCount, 1);
      expect(courseB.notReportedExceededDeadlineCount, 1);

      await _insertActivityRowOnly(
        database,
        key: 'removed',
        courseId: 3001,
        dueDate: '2026-08-04T12:00:00Z',
        dueDateExceed: false,
      );
      catalog = await store.readActiveCatalog();
      courseA = catalog.courses.firstWhere(
        (course) => course.key.courseId == 3001,
      );
      expect(courseA.postBaselineActivityCount, 3);
      expect(courseA.notReportedExceededDeadlineCount, 2);
    },
  );

  test(
    'writes each field independently and survives store reconstruction',
    () async {
      await _insertSemester(database, 101, active: true);
      await _insertCourse(database, 101, 3001, 'Course A');
      const key = CourseKey(semesterId: 101, courseId: 3001);

      expect(
        await store.setNotificationsMuted(key, muted: true),
        isA<CoursePreferenceWriteApplied>(),
      );
      expect(
        await store.setBackgroundMonitoringEnabled(key, enabled: false),
        isA<CoursePreferenceWriteApplied>(),
      );

      final preference = await store.readCurrentCoursePreference(key);
      expect(
        preference,
        const CoursePreference(
          notificationsMuted: true,
          backgroundMonitoringEnabled: false,
        ),
      );
      final reopenedStore = DriftCoursePreferencesStore(database);
      expect(await reopenedStore.readCurrentCoursePreference(key), preference);

      await store.setNotificationsMuted(key, muted: false);
      expect(
        await store.readCurrentCoursePreference(key),
        const CoursePreference(backgroundMonitoringEnabled: false),
      );
      await store.setBackgroundMonitoringEnabled(key, enabled: true);
      expect(
        await store.readCurrentCoursePreference(key),
        const CoursePreference(),
      );
    },
  );

  test(
    'fences writes against active-semester and current-course changes',
    () async {
      await _insertSemester(database, 101, active: true);
      await _insertSemester(database, 102);
      await _insertCourse(database, 101, 3001, 'Course A');
      const key = CourseKey(semesterId: 101, courseId: 3001);

      await database.customStatement(
        'UPDATE app_settings SET active_semester_id = 102',
      );
      expect(
        await store.setNotificationsMuted(key, muted: true),
        isA<CoursePreferenceWriteStale>(),
      );

      await database.customStatement(
        'UPDATE app_settings SET active_semester_id = 101',
      );
      await database.customStatement(
        'DELETE FROM courses WHERE semester_id = 101 AND course_id = 3001',
      );
      expect(
        await store.setBackgroundMonitoringEnabled(key, enabled: false),
        isA<CoursePreferenceWriteStale>(),
      );
      expect(await database.select(database.coursePreferences).get(), isEmpty);
    },
  );

  test(
    'retains preference while a current course disappears and reappears',
    () async {
      await _insertSemester(database, 101, active: true);
      await _insertCourse(database, 101, 3001, 'Course A');
      const key = CourseKey(semesterId: 101, courseId: 3001);
      await store.setNotificationsMuted(key, muted: true);

      await database.customStatement(
        'DELETE FROM courses WHERE semester_id = 101 AND course_id = 3001',
      );
      expect((await store.readActiveCatalog()).courses, isEmpty);
      expect(
        await database.select(database.coursePreferences).get(),
        hasLength(1),
      );

      await _insertCourse(database, 101, 3001, 'Course A returned');
      final summary = (await store.readActiveCatalog()).courses.single;
      expect(summary.preference.notificationsMuted, isTrue);
    },
  );

  test(
    'watch emits only the committed aggregate after a transaction',
    () async {
      await _insertSemester(database, 101, active: true);
      await _insertCourse(database, 101, 3001, 'Course A');
      final events = <ActiveCourseCatalog>[];
      final firstEvent = Completer<void>();
      final secondEvent = Completer<void>();
      final subscription = store.watchActiveCatalog().listen((catalog) {
        events.add(catalog);
        if (events.length == 1 && !firstEvent.isCompleted) {
          firstEvent.complete();
        }
        if (events.length == 2 && !secondEvent.isCompleted) {
          secondEvent.complete();
        }
      });
      addTearDown(subscription.cancel);
      await firstEvent.future;
      await Future<void>.delayed(Duration.zero);

      await database.transaction(() async {
        await _insertActivity(
          database,
          key: 'committed',
          courseId: 3001,
          dueDate: '2026-08-01',
          dueDateExceed: false,
          isBaseline: false,
        );
        expect(events, hasLength(1));
      });
      await secondEvent.future;

      expect(events, hasLength(2));
      expect(events.last.courses.single.postBaselineActivityCount, 1);
      expect(events.last.courses.single.notReportedExceededDeadlineCount, 1);
    },
  );

  test(
    'policy reads defaults, explicit monitoring, and only current courses',
    () async {
      await _insertSemester(database, 101, active: true);
      await _insertCourse(database, 101, 3001, 'Course A');
      await _insertCourse(database, 101, 3002, 'Course B');
      const first = CourseKey(semesterId: 101, courseId: 3001);
      const second = CourseKey(semesterId: 101, courseId: 3002);

      expect(
        await store.readCurrentCoursePreference(first),
        const CoursePreference(),
      );
      expect(
        await store.readCurrentCoursePreference(
          const CourseKey(semesterId: 101, courseId: 9999),
        ),
        isNull,
      );
      await store.setBackgroundMonitoringEnabled(second, enabled: false);
      expect(await store.readBackgroundMonitoredCourses(101), {first});
    },
  );

  test(
    'validates identifiers and maps storage failures without leaking data',
    () async {
      for (final key in [
        const CourseKey(semesterId: 0, courseId: 1),
        const CourseKey(semesterId: 1, courseId: 0),
        const CourseKey(semesterId: 2147483648, courseId: 1),
      ]) {
        expect(
          () => store.readCurrentCoursePreference(key),
          throwsArgumentError,
        );
      }

      await database.customStatement('DROP TABLE course_preferences');
      await expectLater(
        store.readActiveCatalog(),
        throwsA(
          isA<CoursePreferencesStoreException>().having(
            (error) => error.operation,
            'operation',
            CoursePreferencesStoreOperation.readCatalog,
          ),
        ),
      );
      expect(store.toString(), 'DriftCoursePreferencesStore(redacted: true)');
      expect(
        const CoursePreferencesStoreException(
          CoursePreferencesStoreOperation.writePreference,
        ).toString(),
        'CoursePreferencesStoreException('
        'operation: writePreference, redacted: true)',
      );
    },
  );
}

Future<void> _insertSemester(
  AppDatabase database,
  int semesterId, {
  bool active = false,
}) async {
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: drift.Value(semesterId)));
  if (active) {
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(
            singletonId: const drift.Value(1),
            activeSemesterId: drift.Value(semesterId),
          ),
        );
  }
}

Future<void> _insertCourse(
  AppDatabase database,
  int semesterId,
  int courseId,
  String name,
) {
  return database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: semesterId,
          courseId: courseId,
          name: name,
        ),
      );
}

Future<void> _insertSeenOnly(
  AppDatabase database, {
  required String key,
  required int courseId,
  required bool isBaseline,
}) {
  final now = DateTime.utc(2026, 7, 26);
  return database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: key,
          courseId: courseId,
          firstSeenAtUtc: now,
          lastSeenAtUtc: now,
          isBaseline: isBaseline,
        ),
      );
}

Future<void> _insertActivity(
  AppDatabase database, {
  required String key,
  required int courseId,
  required String? dueDate,
  required bool dueDateExceed,
  required bool isBaseline,
  String? submittedJson,
}) async {
  await _insertSeenOnly(
    database,
    key: key,
    courseId: courseId,
    isBaseline: isBaseline,
  );
  await _insertActivityRowOnly(
    database,
    key: key,
    courseId: courseId,
    dueDate: dueDate,
    dueDateExceed: dueDateExceed,
    submittedJson: submittedJson,
  );
}

Future<void> _insertActivityRowOnly(
  AppDatabase database, {
  required String key,
  required int courseId,
  required String? dueDate,
  required bool dueDateExceed,
  String? submittedJson,
}) {
  return database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: key,
          courseId: courseId,
          backendActivityId: const drift.Value(null),
          userId: 2001,
          advStarred: 0,
          groupType: 'individual',
          activityType: 'ASM',
          peerAssessment: 0,
          isAllowRepeat: 0,
          title: 'Assignment',
          description: '',
          startDateSource: const drift.Value(null),
          dueDateSource: drift.Value(dueDate),
          editGroupMode: '',
          createdAtSource: '2026-07-26',
          userValue: 2001,
          activitySubmissionId: const drift.Value(null),
          classUserId: 4001,
          activityGroupId: const drift.Value(null),
          activityGroupName: const drift.Value(null),
          activitySubmissionSubmittedAtJson: drift.Value(submittedJson),
          dueDateExceed: dueDateExceed,
          quizSubmissionIsSubmitted: submittedJson != null,
          countGroupMember: 1,
          activitySubmissionIsLate: false,
          fileActivitiesJson: '[]',
          questionsJson: '[]',
          submissionsJson: '[]',
          lastDueDateNotificationDateSource: const drift.Value(null),
          lastStatusChangeNotificationDateSource: const drift.Value(null),
          previousSubmissionStatus: const drift.Value(null),
        ),
      );
}
