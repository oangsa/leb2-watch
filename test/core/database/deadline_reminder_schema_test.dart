import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('fresh v9 schema seeds checked reminder singletons', () async {
    expect(database.schemaVersion, 9);

    final preferences = await database
        .select(database.deadlineReminderPreferences)
        .getSingle();
    expect(preferences.singletonId, 1);
    expect(preferences.enabled, isTrue);
    expect(preferences.oneHourEnabled, isTrue);
    expect(preferences.twentyFourHoursEnabled, isTrue);

    final reconciliation = await database
        .select(database.deadlineReminderReconciliations)
        .getSingle();
    expect(reconciliation.singletonId, 1);
    expect(reconciliation.requestedGeneration, 0);
    expect(reconciliation.completedGeneration, 0);
    expect(reconciliation.ownerToken, isNull);
    expect(reconciliation.leaseExpiresAtUtc, isNull);
    expect(reconciliation.backgroundEffectsOnly, isFalse);

    final background = await database
        .select(database.backgroundScheduleSettings)
        .getSingle();
    expect(background.singletonId, 1);
    expect(background.monitoringEnabled, isFalse);
    expect(background.installJitterSeconds, isNull);
  });

  test(
    'reconciliation constraints reject invalid ownership and generations',
    () async {
      await expectLater(
        database.customStatement(
          'UPDATE deadline_reminder_reconciliations '
          'SET completed_generation = 1 WHERE singleton_id = 1',
        ),
        throwsException,
      );
      await expectLater(
        database.customStatement(
          'UPDATE deadline_reminder_reconciliations '
          "SET owner_token = 'owner' WHERE singleton_id = 1",
        ),
        throwsException,
      );
      await expectLater(
        database.customStatement(
          'UPDATE deadline_reminder_reconciliations '
          "SET owner_token = '   ', lease_expires_at_utc = 1 "
          'WHERE singleton_id = 1',
        ),
        throwsException,
      );
      await expectLater(
        database.customStatement(
          'INSERT INTO deadline_reminder_preferences '
          '(singleton_id) VALUES (2)',
        ),
        throwsException,
      );
    },
  );

  test(
    'reminder state distinguishes unknown scheduled and cancelled',
    () async {
      final columns = await database
          .customSelect(
            "SELECT name FROM pragma_table_info('scheduled_reminders')",
          )
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        contains('schedule_state'),
      );

      await database.customStatement(
        'INSERT INTO semesters (semester_id) VALUES (101)',
      );
      await database.customStatement(
        'INSERT INTO seen_activities '
        '(semester_id, identity_key, course_id, first_seen_at_utc, '
        'last_seen_at_utc, is_baseline) '
        "VALUES (101, 'backend:1001', 3001, 1, 1, 1)",
      );
      await database.customStatement(
        'INSERT INTO scheduled_reminders '
        '(notification_id, semester_id, identity_key, offset_minutes, '
        'deadline_at_utc, scheduled_for_utc, created_at_utc, '
        'needs_reconciliation, schedule_state) '
        "VALUES (7001, 101, 'backend:1001', 60, 3, 2, 1, 1, 'unknown')",
      );
      await expectLater(
        database.customStatement(
          'UPDATE scheduled_reminders '
          "SET schedule_state = 'unknown', needs_reconciliation = 0 "
          'WHERE notification_id = 7001',
        ),
        throwsException,
      );
      await expectLater(
        database.customStatement(
          'UPDATE scheduled_reminders '
          "SET schedule_state = 'scheduled', needs_reconciliation = 1 "
          'WHERE notification_id = 7001',
        ),
        throwsException,
      );
      await database.customStatement(
        'UPDATE scheduled_reminders '
        "SET schedule_state = 'cancelled', needs_reconciliation = 0 "
        'WHERE notification_id = 7001',
      );
    },
  );

  test('new reminder tables contain no credential-like columns', () async {
    final rows = await database
        .customSelect(
          "SELECT name FROM pragma_table_info('deadline_reminder_preferences') "
          'UNION ALL '
          'SELECT name FROM '
          "pragma_table_info('deadline_reminder_reconciliations')",
        )
        .get();
    final names = rows.map((row) => row.read<String>('name').toLowerCase());

    for (final name in names) {
      expect(name, isNot(contains('password')));
      expect(name, isNot(contains('cookie')));
      expect(name, isNot(contains('authorization')));
      expect(name, isNot(contains('credential')));
    }
  });
}
