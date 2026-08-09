import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

void main() {
  late AppDatabase database;
  final createdAt = DateTime.utc(2026, 8, 1);
  final scheduledFor = DateTime.utc(2026, 8, 2, 11);
  final deadline = DateTime.utc(2026, 8, 2, 12);

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.customStatement(
      'INSERT INTO semesters (semester_id) VALUES (101)',
    );
    for (final (identity, notificationId) in [
      ('backend:1001', 7001),
      ('backend:1002', 7002),
    ]) {
      await database.customStatement(
        'INSERT INTO seen_activities '
        '(semester_id, identity_key, course_id, first_seen_at_utc, '
        'last_seen_at_utc, is_baseline) VALUES (101, ?, 3001, ?, ?, 1)',
        [
          identity,
          createdAt.millisecondsSinceEpoch,
          createdAt.millisecondsSinceEpoch,
        ],
      );
      await database.customStatement(
        'INSERT INTO scheduled_reminders '
        '(notification_id, semester_id, identity_key, offset_minutes, '
        'deadline_at_utc, scheduled_for_utc, created_at_utc, '
        'needs_reconciliation, schedule_state) '
        "VALUES (?, 101, ?, 60, ?, ?, ?, 0, 'cancelled')",
        [
          notificationId,
          identity,
          deadline.millisecondsSinceEpoch,
          scheduledFor.millisecondsSinceEpoch,
          createdAt.millisecondsSinceEpoch,
        ],
      );
    }
  });

  tearDown(() => database.close());

  test(
    'fresh v16 schema exposes bounded event-version metadata and indices',
    () async {
      expect(database.schemaVersion, 21);
      final columns = await database
          .customSelect(
            "SELECT name FROM pragma_table_info("
            "'deadline_reminder_delivery_outbox') ORDER BY cid",
          )
          .get();
      expect(columns.map((row) => row.read<String>('name')), [
        'dedupe_key',
        'notification_id',
        'semester_id',
        'identity_key',
        'offset_minutes',
        'deadline_at_utc',
        'scheduled_for_utc',
        'state',
        'owner_token',
        'lease_expires_at_utc',
        'created_at_utc',
        'last_attempt_at_utc',
        'last_failure_kind',
      ]);
      final indices = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name IN ('scheduled_reminders_event_version', "
            "'deadline_reminder_delivery_one_in_flight', "
            "'deadline_reminder_delivery_queue') ORDER BY name",
          )
          .get();
      expect(indices.map((row) => row.read<String>('name')), hasLength(3));

      for (final column in columns) {
        final name = column.read<String>('name').toLowerCase();
        expect(name, isNot(contains('password')));
        expect(name, isNot(contains('cookie')));
        expect(name, isNot(contains('authorization')));
        expect(name, isNot(contains('credential')));
      }
    },
  );

  test(
    'state constraints enforce one live owner and bounded failures',
    () async {
      await _insertEvent(
        database,
        'first',
        7001,
        'backend:1001',
        state: 'inFlight',
        owner: 'owner-a',
      );
      await expectLater(
        _insertEvent(
          database,
          'second',
          7002,
          'backend:1002',
          state: 'inFlight',
          owner: 'owner-b',
        ),
        throwsException,
      );
      for (final statement in [
        "UPDATE deadline_reminder_delivery_outbox SET state = 'pending'",
        "UPDATE deadline_reminder_delivery_outbox SET owner_token = ''",
        "UPDATE deadline_reminder_delivery_outbox "
            "SET last_failure_kind = 'PRIVATE_RAW_ERROR'",
      ]) {
        await expectLater(database.customStatement(statement), throwsException);
      }
    },
  );

  test(
    'event-version foreign key fences mutation and assignment deletion',
    () async {
      await _insertEvent(database, 'first', 7001, 'backend:1001');

      await expectLater(
        database.customStatement(
          'UPDATE scheduled_reminders SET deadline_at_utc = ? '
          'WHERE notification_id = 7001',
          [deadline.add(const Duration(hours: 1)).millisecondsSinceEpoch],
        ),
        throwsException,
      );

      await database.customStatement(
        "DELETE FROM seen_activities WHERE identity_key = 'backend:1001'",
      );
      expect(
        await database.select(database.deadlineReminderDeliveryOutbox).get(),
        isEmpty,
      );
    },
  );
}

Future<void> _insertEvent(
  AppDatabase database,
  String dedupeKey,
  int notificationId,
  String identityKey, {
  String state = 'pending',
  String? owner,
}) {
  final createdAt = DateTime.utc(2026, 8, 1).millisecondsSinceEpoch;
  final scheduledFor = DateTime.utc(2026, 8, 2, 11).millisecondsSinceEpoch;
  final deadline = DateTime.utc(2026, 8, 2, 12).millisecondsSinceEpoch;
  return database.customStatement(
    'INSERT INTO deadline_reminder_delivery_outbox '
    '(dedupe_key, notification_id, semester_id, identity_key, offset_minutes, '
    'deadline_at_utc, scheduled_for_utc, state, owner_token, '
    'lease_expires_at_utc, created_at_utc, last_attempt_at_utc) '
    'VALUES (?, ?, 101, ?, 60, ?, ?, ?, ?, ?, ?, ?)',
    [
      dedupeKey,
      notificationId,
      identityKey,
      deadline,
      scheduledFor,
      state,
      owner,
      owner == null ? null : createdAt + 30000,
      createdAt,
      owner == null ? null : createdAt,
    ],
  );
}
