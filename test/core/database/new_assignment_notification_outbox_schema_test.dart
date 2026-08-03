import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: const drift.Value(101)));
    for (final identity in ['backend:1001', 'backend:1002']) {
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
    }
  });

  tearDown(() => database.close());

  test('outbox stores only bounded delivery metadata', () async {
    final columns = await database
        .customSelect(
          "SELECT name FROM pragma_table_info("
          "'new_assignment_notification_outbox') ORDER BY cid",
        )
        .get();

    expect(columns.map((row) => row.read<String>('name')), [
      'dedupe_key',
      'semester_id',
      'identity_key',
      'notification_id',
      'state',
      'owner_token',
      'lease_expires_at_utc',
      'created_at_utc',
      'last_attempt_at_utc',
      'last_failure_kind',
    ]);
  });

  test(
    'state constraints and one global in-flight owner are enforced',
    () async {
      final now = DateTime.utc(2026, 7, 26).millisecondsSinceEpoch;
      await database.customStatement(
        'INSERT INTO new_assignment_notification_outbox '
        '(dedupe_key, semester_id, identity_key, notification_id, state, '
        'owner_token, lease_expires_at_utc, created_at_utc, '
        'last_attempt_at_utc) '
        "VALUES ('first', 101, 'backend:1001', 7001, 'inFlight', "
        "'owner-a', ?, ?, ?)",
        [now + 30000, now, now],
      );

      await expectLater(
        database.customStatement(
          'INSERT INTO new_assignment_notification_outbox '
          '(dedupe_key, semester_id, identity_key, notification_id, state, '
          'owner_token, lease_expires_at_utc, created_at_utc, '
          'last_attempt_at_utc) '
          "VALUES ('second', 101, 'backend:1002', 7002, 'inFlight', "
          "'owner-b', ?, ?, ?)",
          [now + 30000, now, now],
        ),
        throwsException,
      );
      for (final statement in [
        "UPDATE new_assignment_notification_outbox SET state = 'pending'",
        "UPDATE new_assignment_notification_outbox SET owner_token = ''",
        "UPDATE new_assignment_notification_outbox "
            "SET last_failure_kind = 'PRIVATE_RAW_ERROR'",
      ]) {
        await expectLater(database.customStatement(statement), throwsException);
      }
    },
  );

  test(
    'notification IDs are unique and assignment deletion cascades',
    () async {
      final now = DateTime.utc(2026, 7, 26).millisecondsSinceEpoch;
      await database.customStatement(
        'INSERT INTO new_assignment_notification_outbox '
        '(dedupe_key, semester_id, identity_key, notification_id, '
        'created_at_utc) VALUES '
        "('first', 101, 'backend:1001', 7001, ?)",
        [now],
      );
      await expectLater(
        database.customStatement(
          'INSERT INTO new_assignment_notification_outbox '
          '(dedupe_key, semester_id, identity_key, notification_id, '
          'created_at_utc) VALUES '
          "('second', 101, 'backend:1002', 7001, ?)",
          [now],
        ),
        throwsException,
      );

      await (database.delete(
        database.seenActivities,
      )..where((row) => row.identityKey.equals('backend:1001'))).go();

      expect(
        await database.select(database.newAssignmentNotificationOutbox).get(),
        isEmpty,
      );
    },
  );
}
