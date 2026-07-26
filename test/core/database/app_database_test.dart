import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  group('schema version 11', () {
    test(
      'creates exactly the owned tables with foreign keys enabled',
      () async {
        final tableRows = await database
            .customSelect(
              "SELECT name FROM sqlite_schema "
              "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
              'ORDER BY name',
            )
            .get();
        final tableNames = tableRows
            .map((row) => row.read<String>('name'))
            .toList();

        expect(database.schemaVersion, 11);
        expect(tableNames, [
          'activities',
          'activity_fingerprints',
          'app_settings',
          'assignment_baselines',
          'background_schedule_settings',
          'course_preferences',
          'courses',
          'deadline_reminder_preferences',
          'deadline_reminder_reconciliations',
          'new_assignment_notification_outbox',
          'new_assignment_notification_preferences',
          'notification_history',
          'scheduled_reminders',
          'seen_activities',
          'semesters',
          'sync_backoff_states',
          'sync_operation_changes',
          'sync_operations',
          'sync_runs',
        ]);
        expect(await _pragmaInt(database, 'user_version'), 11);
        expect(await _pragmaInt(database, 'foreign_keys'), 1);
      },
    );

    test('creates every explicitly named index', () async {
      final rows = await database
          .customSelect(
            "SELECT name FROM sqlite_schema "
            "WHERE type = 'index' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        names,
        containsAll({
          'activities_backend_identity',
          'activities_by_course',
          'seen_activities_by_course_and_last_seen',
          'activity_fingerprints_by_value',
          'scheduled_reminders_by_assignment_offset',
          'scheduled_reminders_by_scheduled_time',
          'scheduled_reminders_pending_reconciliation',
          'notification_history_by_assignment_kind',
          'new_assignment_outbox_notification_id',
          'new_assignment_outbox_one_in_flight',
          'new_assignment_outbox_queue',
          'sync_runs_by_started_time',
          'sync_operations_one_running',
          'sync_operations_one_active_key',
          'sync_operations_queue',
          'sync_operations_terminal_cleanup',
          'sync_operations_operation_semester',
          'sync_backoff_states_by_next_attempt',
        }),
      );
    });

    test('owns no credential or authorization columns', () async {
      const prohibitedColumnFragments = {
        'password',
        'username',
        'cookie',
        'sessioncookie',
        'authorization',
        'token',
      };
      final tableRows = await database
          .customSelect(
            "SELECT name FROM sqlite_schema "
            "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();

      final columnsByTable = <({String table, String column})>{};
      for (final tableRow in tableRows) {
        final tableName = tableRow.read<String>('name');
        final columns = await database
            .customSelect('PRAGMA table_info("$tableName")')
            .get();
        columnsByTable.addAll(
          columns.map((column) {
            return (
              table: tableName,
              column: column
                  .read<String>('name')
                  .toLowerCase()
                  .replaceAll('_', ''),
            );
          }),
        );
      }

      for (final entry in columnsByTable) {
        for (final fragment in prohibitedColumnFragments) {
          if (entry == (table: 'sync_operations', column: 'ownertoken') ||
              entry ==
                  (
                    table: 'deadline_reminder_reconciliations',
                    column: 'ownertoken',
                  ) ||
              entry ==
                  (
                    table: 'new_assignment_notification_outbox',
                    column: 'ownertoken',
                  )) {
            continue;
          }
          expect(entry.column, isNot(contains(fragment)));
        }
      }
    });

    test('enforces course preference ownership and defaults', () async {
      await _insertSemesterAndCourse(database);

      await database
          .into(database.coursePreferences)
          .insert(
            CoursePreferencesCompanion.insert(semesterId: 101, courseId: 3001),
          );
      final preference = await database
          .select(database.coursePreferences)
          .getSingle();
      expect(preference.notificationsMuted, isFalse);
      expect(preference.backgroundMonitoringEnabled, isTrue);

      for (final values in [(0, 3001), (101, 0), (-1, 3001), (101, -1)]) {
        await expectLater(
          database.customStatement(
            'INSERT INTO course_preferences '
            '(semester_id, course_id) VALUES (?, ?)',
            [values.$1, values.$2],
          ),
          throwsException,
        );
      }

      await database.delete(database.courses).go();
      expect(
        await database.select(database.coursePreferences).get(),
        hasLength(1),
        reason: 'temporarily absent courses retain their preferences',
      );
      await database
          .into(database.courses)
          .insert(
            CoursesCompanion.insert(
              semesterId: 101,
              courseId: 3001,
              name: 'Reappeared Course',
            ),
          );
      expect(
        (await database.select(database.coursePreferences).getSingle())
            .notificationsMuted,
        isFalse,
      );

      await database.delete(database.semesters).go();
      expect(await database.select(database.coursePreferences).get(), isEmpty);
    });

    test('constrains lifecycle state and session revisions', () async {
      await database
          .into(database.appSettings)
          .insert(const AppSettingsCompanion(singletonId: drift.Value(1)));
      final setting = await database.select(database.appSettings).getSingle();
      expect(setting.sessionLifecycle, 'unknown');
      expect(setting.sessionRevision, 0);

      for (final statement in [
        "UPDATE app_settings SET session_lifecycle = 'invalid'",
        'UPDATE app_settings SET session_revision = -1',
        'UPDATE app_settings SET session_revision = 2147483648',
      ]) {
        await expectLater(database.customStatement(statement), throwsException);
      }

      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(semesterId: const drift.Value(101)),
          );
      await database
          .into(database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              semesterId: 101,
              userId: 2001,
              reason: 'manualRefresh',
              state: 'queued',
              enqueuedAtUtc: DateTime.utc(2026, 7, 25),
            ),
          );
      expect(
        (await database.select(database.syncOperations).getSingle())
            .sessionRevision,
        0,
      );
      await expectLater(
        database.customStatement(
          'UPDATE sync_operations SET session_revision = -1',
        ),
        throwsException,
      );
    });
  });

  group('synchronization backoff constraints', () {
    setUp(() async {
      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(semesterId: const drift.Value(101)),
          );
    });

    test('accepts coherent state and cascades with its semester', () async {
      final now = DateTime.utc(2026, 7, 25, 12);
      await database
          .into(database.syncBackoffStates)
          .insert(
            SyncBackoffStatesCompanion.insert(
              semesterId: 101,
              userId: 2001,
              consecutiveFailureCount: 1,
              state: 'waiting',
              nextAutomaticAttemptAtUtc: drift.Value(
                now.add(const Duration(minutes: 1)),
              ),
              lastFailureKind: 'networkUnavailable',
              updatedAtUtc: now,
            ),
          );

      await database.delete(database.semesters).go();

      expect(await database.select(database.syncBackoffStates).get(), isEmpty);
    });

    test('rejects invalid counters, states, codecs, and eligibility', () async {
      final now = DateTime.utc(2026, 7, 25, 12).millisecondsSinceEpoch;
      final invalidRows = [
        [0, 'waiting', now + 60000, 'networkUnavailable', null, null],
        [1, 'waiting', null, 'networkUnavailable', null, null],
        [1, 'blocked', now + 60000, 'sessionExpired', null, null],
        [1, 'waiting', now + 60000, 'sessionExpired', null, null],
        [1, 'blocked', null, 'networkUnavailable', null, null],
        [1, 'blocked', null, 'unknown', 'cancelled', null],
        [1, 'waiting', now + 60000, 'rateLimited', null, -1],
      ];

      for (final row in invalidRows) {
        await expectLater(
          database.customStatement(
            'INSERT INTO sync_backoff_states '
            '(semester_id, user_id, consecutive_failure_count, state, '
            'next_automatic_attempt_at_utc, last_failure_kind, '
            'last_failure_detail, last_retry_after_milliseconds, '
            'updated_at_utc) VALUES (?, 2001, ?, ?, ?, ?, ?, ?, ?)',
            [101, ...row, now],
          ),
          throwsException,
          reason: row.toString(),
        );
      }
      expect(await database.select(database.syncBackoffStates).get(), isEmpty);
    });
  });

  group('synchronization operation constraints', () {
    setUp(() async {
      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(semesterId: const drift.Value(101)),
          );
    });

    test('allows one active operation per key and one global owner', () async {
      final now = DateTime.utc(2026, 7, 25);
      await database
          .into(database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              semesterId: 101,
              userId: 2001,
              reason: 'manualRefresh',
              state: 'queued',
              enqueuedAtUtc: now,
            ),
          );

      await expectLater(
        database
            .into(database.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                semesterId: 101,
                userId: 2001,
                reason: 'appResume',
                state: 'queued',
                enqueuedAtUtc: now,
              ),
            ),
        throwsException,
      );

      await database.customStatement(
        "UPDATE sync_operations SET state = 'running', "
        "started_at_utc = ?, owner_token = 'owner-a', "
        'lease_expires_at_utc = ? WHERE operation_id = 1',
        [
          now.millisecondsSinceEpoch,
          now.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
        ],
      );
      await database
          .into(database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              semesterId: 101,
              userId: 2002,
              reason: 'manualRefresh',
              state: 'queued',
              enqueuedAtUtc: now,
            ),
          );

      await expectLater(
        database.customStatement(
          "UPDATE sync_operations SET state = 'running', "
          "started_at_utc = ?, owner_token = 'owner-b', "
          'lease_expires_at_utc = ? WHERE operation_id = 2',
          [
            now.millisecondsSinceEpoch,
            now.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
          ],
        ),
        throwsException,
      );
    });

    test('rejects malformed states and cascades with the semester', () async {
      final now = DateTime.utc(2026, 7, 25);
      await expectLater(
        database
            .into(database.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                semesterId: 101,
                userId: 2001,
                reason: 'unknownReason',
                state: 'queued',
                enqueuedAtUtc: now,
              ),
            ),
        throwsException,
      );
      await database
          .into(database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              semesterId: 101,
              userId: 2001,
              reason: 'manualRefresh',
              state: 'queued',
              enqueuedAtUtc: now,
            ),
          );

      await database.delete(database.semesters).go();

      expect(await database.select(database.syncOperations).get(), isEmpty);
    });

    test('rejects malformed terminal failure metadata', () async {
      final now = DateTime.utc(2026, 7, 25);
      await expectLater(
        database
            .into(database.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                semesterId: 101,
                userId: 2001,
                reason: 'manualRefresh',
                state: 'failure',
                enqueuedAtUtc: now,
                startedAtUtc: drift.Value(now),
                completedAtUtc: drift.Value(now),
                resultFailureKind: const drift.Value('requestTimeout'),
                resultFailureDetail: const drift.Value('notAPhase'),
              ),
            ),
        throwsException,
      );
      for (final kind in ['requestTimeout', 'unknown']) {
        await expectLater(
          database
              .into(database.syncOperations)
              .insert(
                SyncOperationsCompanion.insert(
                  semesterId: 101,
                  userId: 2001,
                  reason: 'manualRefresh',
                  state: 'failure',
                  enqueuedAtUtc: now,
                  startedAtUtc: drift.Value(now),
                  completedAtUtc: drift.Value(now),
                  resultFailureKind: drift.Value(kind),
                ),
              ),
          throwsException,
          reason: '$kind requires a result detail',
        );
      }
      await expectLater(
        database
            .into(database.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                semesterId: 101,
                userId: 2001,
                reason: 'manualRefresh',
                state: 'failure',
                enqueuedAtUtc: now,
                startedAtUtc: drift.Value(now),
                completedAtUtc: drift.Value(now),
                resultFailureKind: const drift.Value('sessionExpired'),
                resultRetryAfterMilliseconds: const drift.Value(1000),
              ),
            ),
        throwsException,
      );
    });
  });

  test(
    'persists, updates, and deletes assignment state with owned cascades',
    () async {
      await _insertSemesterAndCourse(database);
      await database.into(database.activities).insert(_activity());
      await database
          .into(database.seenActivities)
          .insert(
            SeenActivitiesCompanion.insert(
              semesterId: 101,
              identityKey: 'backend:1001',
              courseId: 3001,
              firstSeenAtUtc: DateTime.utc(2026, 7, 1),
              lastSeenAtUtc: DateTime.utc(2026, 7, 2),
              isBaseline: true,
            ),
          );
      await database
          .into(database.activityFingerprints)
          .insert(
            ActivityFingerprintsCompanion.insert(
              semesterId: 101,
              identityKey: 'backend:1001',
              fingerprintVersion: 1,
              fingerprint: 'synthetic-fingerprint',
            ),
          );
      await database
          .into(database.scheduledReminders)
          .insert(
            ScheduledRemindersCompanion.insert(
              notificationId: const drift.Value(7001),
              semesterId: 101,
              identityKey: 'backend:1001',
              offsetMinutes: 60,
              deadlineAtUtc: DateTime.utc(2026, 7, 31, 16, 59),
              scheduledForUtc: DateTime.utc(2026, 7, 31, 15, 59),
              createdAtUtc: DateTime.utc(2026, 7, 2),
            ),
          );
      await database
          .into(database.notificationHistory)
          .insert(
            NotificationHistoryCompanion.insert(
              dedupeKey: 'new:backend:1001',
              semesterId: 101,
              identityKey: 'backend:1001',
              kind: 'new-assignment',
              notificationId: 7002,
              recordedAtUtc: DateTime.utc(2026, 7, 2),
            ),
          );

      await (database.update(database.activities)..where(
            (activity) => drift.Expression.and([
              activity.semesterId.equals(101),
              activity.identityKey.equals('backend:1001'),
            ]),
          ))
          .write(
            const ActivitiesCompanion(title: drift.Value('Updated title')),
          );

      final activity = await database.select(database.activities).getSingle();
      expect(activity.backendActivityId, 1001);
      expect(activity.userId, 2001);
      expect(activity.courseId, 3001);
      expect(activity.advStarred, 0);
      expect(activity.groupType, 'individual');
      expect(activity.activityType, 'ASM');
      expect(activity.peerAssessment, 0);
      expect(activity.isAllowRepeat, 0);
      expect(activity.title, 'Updated title');
      expect(activity.description, '<p>Example description</p>');
      expect(activity.startDateSource, '2026-07-01T09:00:00');
      expect(activity.dueDateSource, '2026-07-31T23:59:00');
      expect(activity.editGroupMode, '');
      expect(activity.createdAtSource, '2026-06-30T12:00:00');
      expect(activity.userValue, 2001);
      expect(activity.activitySubmissionId, 5001);
      expect(activity.classUserId, 4001);
      expect(activity.activityGroupId, 6001);
      expect(activity.activityGroupName, 'Example group');
      expect(
        activity.activitySubmissionSubmittedAtJson,
        '{"date":"2026-07-20 10:30:00.000000",'
        '"timezoneType":3,"timezone":"Asia/Bangkok"}',
      );
      expect(activity.dueDateExceed, isFalse);
      expect(activity.quizSubmissionIsSubmitted, isFalse);
      expect(activity.countGroupMember, 1);
      expect(activity.activitySubmissionIsLate, isFalse);
      expect(activity.fileActivitiesJson, '[]');
      expect(activity.questionsJson, '[1,2]');
      expect(activity.submissionsJson, '[]');
      expect(activity.lastDueDateNotificationDateSource, '2026-07-30T23:59:00');
      expect(
        activity.lastStatusChangeNotificationDateSource,
        '2026-07-20T10:30:00',
      );
      expect(activity.previousSubmissionStatus, isTrue);

      await (database.delete(database.activities)..where(
            (row) => drift.Expression.and([
              row.semesterId.equals(101),
              row.identityKey.equals('backend:1001'),
            ]),
          ))
          .go();

      expect(
        await database.select(database.scheduledReminders).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.seenActivities).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.activityFingerprints).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.notificationHistory).get(),
        hasLength(1),
      );

      await database.delete(database.courses).go();
      expect(
        await database.select(database.seenActivities).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.activityFingerprints).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.notificationHistory).get(),
        hasLength(1),
      );

      await database.delete(database.seenActivities).go();
      expect(await database.select(database.scheduledReminders).get(), isEmpty);
      expect(
        await database.select(database.activityFingerprints).get(),
        isEmpty,
      );
      expect(
        await database.select(database.notificationHistory).get(),
        isEmpty,
      );
    },
  );

  group('foreign-key and check enforcement', () {
    test('rejects a course without its semester', () async {
      await expectLater(
        database
            .into(database.courses)
            .insert(
              CoursesCompanion.insert(
                semesterId: 101,
                courseId: 3001,
                name: 'Example Course',
              ),
            ),
        throwsException,
      );
    });

    test('rejects an activity without its composite course', () async {
      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(semesterId: const drift.Value(101)),
          );

      await expectLater(
        database.into(database.activities).insert(_activity()),
        throwsException,
      );
    });

    test(
      'semester deletion cascades state and clears active selection',
      () async {
        await _insertSemesterAndCourse(database);
        await database.into(database.activities).insert(_activity());
        await database
            .into(database.seenActivities)
            .insert(
              SeenActivitiesCompanion.insert(
                semesterId: 101,
                identityKey: 'backend:1001',
                courseId: 3001,
                firstSeenAtUtc: DateTime.utc(2026, 7, 1),
                lastSeenAtUtc: DateTime.utc(2026, 7, 1),
                isBaseline: true,
              ),
            );
        await database
            .into(database.activityFingerprints)
            .insert(
              ActivityFingerprintsCompanion.insert(
                semesterId: 101,
                identityKey: 'backend:1001',
                fingerprintVersion: 1,
                fingerprint: 'synthetic-fingerprint',
              ),
            );
        await database
            .into(database.scheduledReminders)
            .insert(
              ScheduledRemindersCompanion.insert(
                notificationId: const drift.Value(7001),
                semesterId: 101,
                identityKey: 'backend:1001',
                offsetMinutes: 60,
                deadlineAtUtc: DateTime.utc(2026, 7, 31),
                scheduledForUtc: DateTime.utc(2026, 7, 30, 23),
                createdAtUtc: DateTime.utc(2026, 7, 1),
              ),
            );
        await database
            .into(database.notificationHistory)
            .insert(
              NotificationHistoryCompanion.insert(
                dedupeKey: 'new:backend:1001',
                semesterId: 101,
                identityKey: 'backend:1001',
                kind: 'new-assignment',
                notificationId: 7002,
                recordedAtUtc: DateTime.utc(2026, 7, 1),
              ),
            );
        await database.createSyncRun(
          semesterId: 101,
          reason: 'manual-refresh',
          outcome: 'success',
          startedAtUtc: DateTime.utc(2026, 7, 1),
        );
        await database
            .into(database.assignmentBaselines)
            .insert(
              AssignmentBaselinesCompanion.insert(
                semesterId: const drift.Value(101),
                establishedAtUtc: drift.Value(DateTime.utc(2026, 7, 1)),
              ),
            );
        final operationId = await database
            .into(database.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                semesterId: 101,
                userId: 2001,
                reason: 'manualRefresh',
                state: 'success',
                enqueuedAtUtc: DateTime.utc(2026, 7, 1),
                startedAtUtc: drift.Value(DateTime.utc(2026, 7, 1)),
                completedAtUtc: drift.Value(DateTime.utc(2026, 7, 1)),
                resultCourseCount: const drift.Value(1),
                resultActivityCount: const drift.Value(1),
              ),
            );
        await database
            .into(database.syncOperationChanges)
            .insert(
              SyncOperationChangesCompanion.insert(
                operationId: operationId,
                semesterId: 101,
                identityKey: 'backend:1001',
                kind: 'newActivity',
              ),
            );
        await database
            .into(database.appSettings)
            .insert(
              const AppSettingsCompanion(
                singletonId: drift.Value(1),
                activeSemesterId: drift.Value(101),
              ),
            );

        await database.delete(database.semesters).go();

        expect(await database.select(database.courses).get(), isEmpty);
        expect(await database.select(database.activities).get(), isEmpty);
        expect(await database.select(database.seenActivities).get(), isEmpty);
        expect(
          await database.select(database.activityFingerprints).get(),
          isEmpty,
        );
        expect(
          await database.select(database.scheduledReminders).get(),
          isEmpty,
        );
        expect(
          await database.select(database.notificationHistory).get(),
          isEmpty,
        );
        expect(await database.select(database.syncRuns).get(), isEmpty);
        expect(
          await database.select(database.assignmentBaselines).get(),
          isEmpty,
        );
        expect(
          await database.select(database.syncOperationChanges).get(),
          isEmpty,
        );
        expect(
          (await database.select(database.appSettings).getSingle())
              .activeSemesterId,
          isNull,
        );
      },
    );

    test(
      'change kinds and reminder ownership follow durable ledger constraints',
      () async {
        await _insertSemesterAndCourse(database);
        await database.into(database.activities).insert(_activity());
        await database
            .into(database.seenActivities)
            .insert(
              SeenActivitiesCompanion.insert(
                semesterId: 101,
                identityKey: 'backend:1001',
                courseId: 3001,
                firstSeenAtUtc: DateTime.utc(2026, 7, 1),
                lastSeenAtUtc: DateTime.utc(2026, 7, 1),
                isBaseline: true,
              ),
            );
        final operationId = await database
            .into(database.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                semesterId: 101,
                userId: 2001,
                reason: 'manualRefresh',
                state: 'success',
                enqueuedAtUtc: DateTime.utc(2026, 7, 1),
                startedAtUtc: drift.Value(DateTime.utc(2026, 7, 1)),
                completedAtUtc: drift.Value(DateTime.utc(2026, 7, 1)),
                resultCourseCount: const drift.Value(1),
                resultActivityCount: const drift.Value(1),
              ),
            );
        await database
            .into(database.syncOperationChanges)
            .insert(
              SyncOperationChangesCompanion.insert(
                operationId: operationId,
                semesterId: 101,
                identityKey: 'backend:1001',
                kind: 'removed',
              ),
            );
        await expectLater(
          database
              .into(database.syncOperationChanges)
              .insert(
                SyncOperationChangesCompanion.insert(
                  operationId: operationId,
                  semesterId: 101,
                  identityKey: 'backend:1001',
                  kind: 'unknown',
                ),
              ),
          throwsException,
        );
        await database
            .into(database.scheduledReminders)
            .insert(
              ScheduledRemindersCompanion.insert(
                notificationId: const drift.Value(7001),
                semesterId: 101,
                identityKey: 'backend:1001',
                offsetMinutes: 60,
                deadlineAtUtc: DateTime.utc(2026, 7, 31),
                scheduledForUtc: DateTime.utc(2026, 7, 30),
                createdAtUtc: DateTime.utc(2026, 7, 1),
              ),
            );

        await database.delete(database.activities).go();
        expect(
          await database.select(database.scheduledReminders).get(),
          hasLength(1),
        );
        await (database.delete(
          database.syncOperations,
        )..where((row) => row.operationId.equals(operationId))).go();
        expect(
          await database.select(database.syncOperationChanges).get(),
          isEmpty,
        );
        await database.delete(database.seenActivities).go();
        expect(
          await database.select(database.scheduledReminders).get(),
          isEmpty,
        );
      },
    );

    test(
      'rejects change evidence owned by a different operation semester',
      () async {
        await _insertSemesterAndCourse(database);
        await _insertSemesterAndCourse(
          database,
          semesterId: 102,
          courseId: 3002,
        );
        await database
            .into(database.seenActivities)
            .insert(
              SeenActivitiesCompanion.insert(
                semesterId: 102,
                identityKey: 'backend:2002',
                courseId: 3002,
                firstSeenAtUtc: DateTime.utc(2026, 7, 1),
                lastSeenAtUtc: DateTime.utc(2026, 7, 1),
                isBaseline: false,
              ),
            );
        final operationId = await database
            .into(database.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                semesterId: 101,
                userId: 2001,
                reason: 'manualRefresh',
                state: 'success',
                enqueuedAtUtc: DateTime.utc(2026, 7, 1),
                startedAtUtc: drift.Value(DateTime.utc(2026, 7, 1)),
                completedAtUtc: drift.Value(DateTime.utc(2026, 7, 1)),
                resultCourseCount: const drift.Value(1),
                resultActivityCount: const drift.Value(1),
              ),
            );

        await expectLater(
          database
              .into(database.syncOperationChanges)
              .insert(
                SyncOperationChangesCompanion.insert(
                  operationId: operationId,
                  semesterId: 102,
                  identityKey: 'backend:2002',
                  kind: 'newActivity',
                ),
              ),
          throwsException,
        );
      },
    );

    test('rejects invalid identifiers and blank owned values', () async {
      await expectLater(
        database
            .into(database.semesters)
            .insert(
              SemestersCompanion.insert(semesterId: const drift.Value(0)),
            ),
        throwsException,
      );
      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(semesterId: const drift.Value(101)),
          );
      await expectLater(
        database
            .into(database.courses)
            .insert(
              CoursesCompanion.insert(
                semesterId: 101,
                courseId: 3001,
                name: '   ',
              ),
            ),
        throwsException,
      );
    });
  });

  test('rolls back all writes when a transaction fails', () async {
    await expectLater(
      database.transaction(() async {
        await database
            .into(database.semesters)
            .insert(
              SemestersCompanion.insert(semesterId: const drift.Value(101)),
            );
        await database
            .into(database.courses)
            .insert(
              CoursesCompanion.insert(
                semesterId: 101,
                courseId: 3001,
                name: 'Example Course',
              ),
            );
        throw StateError('synthetic rollback');
      }),
      throwsStateError,
    );

    expect(await database.select(database.semesters).get(), isEmpty);
    expect(await database.select(database.courses).get(), isEmpty);
  });

  test('stores app-owned timestamps as UTC epoch milliseconds', () async {
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
    final localTimestamp = DateTime(2026, 7, 25, 15, 30, 12, 345);

    await database.createSyncRun(
      semesterId: 101,
      reason: 'manual-refresh',
      outcome: 'success',
      startedAtUtc: localTimestamp,
    );

    final raw = await database
        .customSelect('SELECT started_at_utc FROM sync_runs')
        .getSingle();
    final stored = await database.select(database.syncRuns).getSingle();
    expect(
      raw.read<int>('started_at_utc'),
      localTimestamp.toUtc().millisecondsSinceEpoch,
    );
    expect(stored.startedAtUtc.isUtc, isTrue);
    expect(stored.startedAtUtc, localTimestamp.toUtc());
  });

  test(
    'supports backend and fingerprint identities without collisions',
    () async {
      await _insertSemesterAndCourse(database);
      await database.into(database.activities).insert(_activity());
      await database
          .into(database.activities)
          .insert(
            _activity(
              identityKey: 'fingerprint:v1:synthetic',
              backendActivityId: const drift.Value(null),
              title: 'Fallback identity',
            ),
          );
      await database
          .into(database.seenActivities)
          .insert(
            SeenActivitiesCompanion.insert(
              semesterId: 101,
              identityKey: 'fingerprint:v1:synthetic',
              courseId: 3001,
              firstSeenAtUtc: DateTime.utc(2026, 7, 2),
              lastSeenAtUtc: DateTime.utc(2026, 7, 2),
              isBaseline: false,
            ),
          );
      await database
          .into(database.activityFingerprints)
          .insert(
            ActivityFingerprintsCompanion.insert(
              semesterId: 101,
              identityKey: 'fingerprint:v1:synthetic',
              fingerprintVersion: 1,
              fingerprint: 'synthetic-fingerprint',
            ),
          );

      expect(await database.select(database.activities).get(), hasLength(2));
      expect(
        await database.select(database.activityFingerprints).get(),
        hasLength(1),
      );
      await database
          .into(database.seenActivities)
          .insert(
            SeenActivitiesCompanion.insert(
              semesterId: 101,
              identityKey: 'fingerprint:v1:other',
              courseId: 3001,
              firstSeenAtUtc: DateTime.utc(2026, 7, 2),
              lastSeenAtUtc: DateTime.utc(2026, 7, 2),
              isBaseline: false,
            ),
          );
      await expectLater(
        database
            .into(database.activityFingerprints)
            .insert(
              ActivityFingerprintsCompanion.insert(
                semesterId: 101,
                identityKey: 'fingerprint:v1:other',
                fingerprintVersion: 1,
                fingerprint: 'synthetic-fingerprint',
              ),
            ),
        throwsException,
        reason: 'one fingerprint cannot alias two assignment identities',
      );

      await expectLater(
        database
            .into(database.activities)
            .insert(
              _activity(
                identityKey: 'another-key',
                backendActivityId: const drift.Value(1001),
              ),
            ),
        throwsException,
      );

      await _insertSemesterAndCourse(database, semesterId: 102, courseId: 3001);
      await database
          .into(database.activities)
          .insert(
            _activity(
              semesterId: 102,
              identityKey: 'backend:1001',
              courseId: 3001,
              backendActivityId: const drift.Value(1001),
            ),
          );
      expect(await database.select(database.activities).get(), hasLength(3));
    },
  );

  test('retains by timestamp first and run ID second for ties', () async {
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
    final baseTime = DateTime.utc(2026, 7, 25);
    final chronologicalIds = <int>[];

    for (var index = 0; index < syncRunRetentionLimit - 2; index++) {
      chronologicalIds.add(
        await database.createSyncRun(
          semesterId: 101,
          reason: 'manual-refresh',
          outcome: 'success',
          startedAtUtc: baseTime.add(Duration(minutes: index)),
        ),
      );
    }

    final tiedNewestTime = baseTime.add(const Duration(days: 2));
    final firstTiedId = await database.createSyncRun(
      semesterId: 101,
      reason: 'manual-refresh',
      outcome: 'success',
      startedAtUtc: tiedNewestTime,
    );
    final secondTiedId = await database.createSyncRun(
      semesterId: 101,
      reason: 'manual-refresh',
      outcome: 'success',
      startedAtUtc: tiedNewestTime,
    );
    final lateOlderId = await database.createSyncRun(
      semesterId: 101,
      reason: 'manual-refresh',
      outcome: 'success',
      startedAtUtc: baseTime.subtract(const Duration(days: 1)),
    );
    final thirdTiedId = await database.createSyncRun(
      semesterId: 101,
      reason: 'manual-refresh',
      outcome: 'success',
      startedAtUtc: tiedNewestTime,
    );

    final retained =
        await (database.select(database.syncRuns)..orderBy([
              (row) => drift.OrderingTerm.desc(row.startedAtUtc),
              (row) => drift.OrderingTerm.desc(row.syncRunId),
            ]))
            .get();
    expect(retained, hasLength(syncRunRetentionLimit));
    expect(retained.take(3).map((run) => run.syncRunId), [
      thirdTiedId,
      secondTiedId,
      firstTiedId,
    ]);
    expect(retained.map((run) => run.syncRunId), isNot(contains(lateOlderId)));
    expect(
      retained.map((run) => run.syncRunId),
      isNot(contains(chronologicalIds.first)),
    );
    expect(retained.last.syncRunId, chronologicalIds[1]);
  });

  test('rolls back sync-run insertion when pruning fails', () async {
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
    final baseTime = DateTime.utc(2026, 7, 25);
    for (var index = 0; index < syncRunRetentionLimit; index++) {
      await database.createSyncRun(
        semesterId: 101,
        reason: 'manual-refresh',
        outcome: 'success',
        startedAtUtc: baseTime.add(Duration(minutes: index)),
      );
    }
    final newestExistingId =
        (await (database.select(database.syncRuns)
                  ..orderBy([(row) => drift.OrderingTerm.desc(row.syncRunId)])
                  ..limit(1))
                .getSingle())
            .syncRunId;
    final attemptedTime = baseTime.add(const Duration(days: 7));

    await database.customStatement(
      'CREATE TRIGGER abort_sync_run_prune '
      'BEFORE DELETE ON sync_runs '
      'BEGIN '
      "SELECT RAISE(ABORT, 'synthetic prune failure'); "
      'END',
    );
    try {
      await expectLater(
        database.createSyncRun(
          semesterId: 101,
          reason: 'manual-refresh',
          outcome: 'success',
          startedAtUtc: attemptedTime,
        ),
        throwsException,
      );

      final retained = await database.select(database.syncRuns).get();
      expect(retained, hasLength(syncRunRetentionLimit));
      expect(
        retained.map((run) => run.syncRunId),
        everyElement(lessThanOrEqualTo(newestExistingId)),
      );
      expect(
        retained.map((run) => run.startedAtUtc),
        isNot(contains(attemptedTime)),
      );
    } finally {
      await database.customStatement(
        'DROP TRIGGER IF EXISTS abort_sync_run_prune',
      );
    }
  });
}

Future<int> _pragmaInt(AppDatabase database, String pragma) async {
  final row = await database.customSelect('PRAGMA $pragma').getSingle();
  return row.data.values.single as int;
}

Future<void> _insertSemesterAndCourse(
  AppDatabase database, {
  int semesterId = 101,
  int courseId = 3001,
}) async {
  await database
      .into(database.semesters)
      .insert(SemestersCompanion.insert(semesterId: drift.Value(semesterId)));
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: semesterId,
          courseId: courseId,
          name: 'Example Course',
        ),
      );
}

ActivitiesCompanion _activity({
  int semesterId = 101,
  String identityKey = 'backend:1001',
  int courseId = 3001,
  drift.Value<int?> backendActivityId = const drift.Value(1001),
  String title = 'Example assignment',
}) {
  return ActivitiesCompanion.insert(
    semesterId: semesterId,
    identityKey: identityKey,
    courseId: courseId,
    backendActivityId: backendActivityId,
    userId: 2001,
    advStarred: 0,
    groupType: 'individual',
    activityType: 'ASM',
    peerAssessment: 0,
    isAllowRepeat: 0,
    title: title,
    description: '<p>Example description</p>',
    startDateSource: const drift.Value('2026-07-01T09:00:00'),
    dueDateSource: const drift.Value('2026-07-31T23:59:00'),
    editGroupMode: '',
    createdAtSource: '2026-06-30T12:00:00',
    userValue: 2001,
    activitySubmissionId: const drift.Value(5001),
    classUserId: 4001,
    activityGroupId: const drift.Value(6001),
    activityGroupName: const drift.Value('Example group'),
    activitySubmissionSubmittedAtJson: const drift.Value(
      '{"date":"2026-07-20 10:30:00.000000",'
      '"timezoneType":3,"timezone":"Asia/Bangkok"}',
    ),
    dueDateExceed: false,
    quizSubmissionIsSubmitted: false,
    countGroupMember: 1,
    activitySubmissionIsLate: false,
    fileActivitiesJson: '[]',
    questionsJson: '[1,2]',
    submissionsJson: '[]',
    lastDueDateNotificationDateSource: const drift.Value('2026-07-30T23:59:00'),
    lastStatusChangeNotificationDateSource: const drift.Value(
      '2026-07-20T10:30:00',
    ),
    previousSubmissionStatus: const drift.Value(true),
  );
}
