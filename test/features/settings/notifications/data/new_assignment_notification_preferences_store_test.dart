import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/notifications/data/new_assignment_notification_store.dart';
import 'package:leb2_watch/src/features/settings/notifications/data/new_assignment_notification_preferences_store.dart';

void main() {
  late AppDatabase database;
  late DriftNewAssignmentNotificationPreferencesStore preferences;
  late DriftNewAssignmentNotificationStore notifications;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    preferences = DriftNewAssignmentNotificationPreferencesStore(
      database,
      clock: () => DateTime.utc(2026, 7, 26, 2),
    );
    notifications = DriftNewAssignmentNotificationStore(database);
  });

  tearDown(() => database.close());

  test('watch starts enabled and emits persisted changes', () async {
    final values = <bool>[];
    final subscription = preferences
        .watch()
        .map((setting) => setting.enabled)
        .listen(values.add);
    addTearDown(subscription.cancel);

    await Future<void>.delayed(Duration.zero);
    await preferences.setEnabled(false);
    await Future<void>.delayed(Duration.zero);

    expect(values, [true, false]);
  });

  test('disable consumes every currently unclaimed discovery', () async {
    await _seedCurrent(database, id: 1001);
    await _seedCurrent(database, id: 1002);

    await preferences.setEnabled(false);

    final history = await database.select(database.notificationHistory).get();
    expect(history, hasLength(2));
    expect(history.map((row) => row.kind).toSet(), {
      disabledNewAssignmentNotificationKind,
    });
    expect(await _claim(notifications), isNull);
  });

  test('re-enable consumes work discovered while disabled', () async {
    await preferences.setEnabled(false);
    await _seedCurrent(database, id: 1001);

    await preferences.setEnabled(true);

    expect(
      (await database.select(database.notificationHistory).getSingle()).kind,
      disabledNewAssignmentNotificationKind,
    );
    expect(await _claim(notifications), isNull);
    expect((await preferences.watch().first).enabled, isTrue);
  });

  test('disable racing a claim records one canonical outcome', () async {
    await _seedCurrent(database, id: 1001);

    await Future.wait<Object?>([
      _claim(notifications),
      preferences.setEnabled(false),
    ]);

    final history = await database.select(database.notificationHistory).get();
    expect(history, hasLength(1));
    expect(history.single.kind, disabledNewAssignmentNotificationKind);
    expect(
      await database.select(database.newAssignmentNotificationOutbox).get(),
      isEmpty,
    );
    expect(await _claim(notifications, ownerToken: 'owner-b'), isNull);
  });

  test(
    'removed discovery stays consumed across disable re-enable and reappear',
    () async {
      await _seedCurrent(database, id: 1001);
      final retainedActivity = await database
          .select(database.activities)
          .getSingle();
      await database.delete(database.activities).go();

      expect(
        await database.select(database.seenActivities).get(),
        hasLength(1),
      );
      await preferences.setEnabled(false);
      await preferences.setEnabled(true);

      final suppressedHistory = await database
          .select(database.notificationHistory)
          .get();
      expect(suppressedHistory, hasLength(1));
      expect(
        suppressedHistory.single.kind,
        disabledNewAssignmentNotificationKind,
      );
      expect(suppressedHistory.single.semesterId, 101);
      expect(suppressedHistory.single.identityKey, 'backend:1001');

      await database.into(database.activities).insert(retainedActivity);

      expect(await _claim(notifications), isNull);
      final finalHistory = await database
          .select(database.notificationHistory)
          .get();
      expect(finalHistory, hasLength(1));
      expect(finalHistory.single.dedupeKey, suppressedHistory.single.dedupeKey);
      expect(finalHistory.single.identityKey, 'backend:1001');
    },
  );
}

Future<NewAssignmentNotificationClaim?> _claim(
  NewAssignmentNotificationStore store, {
  String ownerToken = 'owner-a',
}) {
  return store.claimNext(
    semesterId: 101,
    ownerToken: ownerToken,
    nowUtc: DateTime.utc(2026, 7, 26, 2),
    leaseDuration: const Duration(seconds: 30),
  );
}

Future<void> _seedCurrent(AppDatabase database, {required int id}) async {
  await database
      .into(database.semesters)
      .insert(
        SemestersCompanion.insert(semesterId: const drift.Value(101)),
        mode: drift.InsertMode.insertOrIgnore,
      );
  await database
      .into(database.courses)
      .insert(
        CoursesCompanion.insert(
          semesterId: 101,
          courseId: 3001,
          name: 'Course 3001',
        ),
        mode: drift.InsertMode.insertOrIgnore,
      );
  final identity = 'backend:$id';
  await database
      .into(database.seenActivities)
      .insert(
        SeenActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: identity,
          courseId: 3001,
          firstSeenAtUtc: DateTime.utc(2026, 7, 26),
          lastSeenAtUtc: DateTime.utc(2026, 7, 26),
          isBaseline: false,
        ),
      );
  await database
      .into(database.activities)
      .insert(
        ActivitiesCompanion.insert(
          semesterId: 101,
          identityKey: identity,
          courseId: 3001,
          backendActivityId: drift.Value(id),
          userId: 2001,
          advStarred: 0,
          groupType: 'individual',
          activityType: 'ASM',
          peerAssessment: 0,
          isAllowRepeat: 0,
          title: 'Assignment $id',
          description: '',
          startDateSource: const drift.Value(null),
          dueDateSource: const drift.Value(null),
          editGroupMode: '',
          createdAtSource: '2026-07-26T00:00:00Z',
          userValue: 2001,
          activitySubmissionId: const drift.Value(null),
          classUserId: 4001,
          activityGroupId: const drift.Value(null),
          activityGroupName: const drift.Value(null),
          activitySubmissionSubmittedAtJson: const drift.Value(null),
          dueDateExceed: false,
          quizSubmissionIsSubmitted: false,
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
