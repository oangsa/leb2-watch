import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

import 'v12_app_database.dart' as v12;

void main() {
  test(
    'real v12 upgrades with reminder ownership intact and empty outbox',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-v12-deadline-delivery-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/leb2_watch.sqlite');
      final now = DateTime.utc(2026, 8, 1).millisecondsSinceEpoch;

      final legacy = v12.V12AppDatabase(NativeDatabase(file));
      await legacy.customStatement(
        'INSERT INTO semesters (semester_id) VALUES (101)',
      );
      await legacy.customStatement(
        'INSERT INTO seen_activities '
        '(semester_id, identity_key, course_id, first_seen_at_utc, '
        'last_seen_at_utc, is_baseline) '
        "VALUES (101, 'backend:1001', 3001, ?, ?, 1)",
        [now, now],
      );
      await legacy.customStatement(
        'INSERT INTO scheduled_reminders '
        '(notification_id, semester_id, identity_key, offset_minutes, '
        'deadline_at_utc, scheduled_for_utc, created_at_utc, '
        'needs_reconciliation, schedule_state) '
        "VALUES (7001, 101, 'backend:1001', 60, ?, ?, ?, 0, 'cancelled')",
        [now + 7200000, now + 3600000, now],
      );
      expect(
        await legacy
            .customSelect(
              "SELECT COUNT(*) AS count FROM sqlite_master "
              "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .getSingle()
            .then((row) => row.read<int>('count')),
        20,
      );
      await legacy.close();

      final database = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(database.close);

      expect(database.schemaVersion, 17);
      expect(
        await database.select(database.scheduledReminders).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.deadlineReminderDeliveryOutbox).get(),
        isEmpty,
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      expect(
        await database
            .customSelect('PRAGMA user_version')
            .getSingle()
            .then((row) => row.read<int>('user_version')),
        17,
      );
    },
  );

  test('v12 fixture is independent of live production tables', () {
    final source = File(
      'test/core/database/v12_app_database.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('database_tables.dart')));
    expect(source, isNot(contains('@DriftDatabase')));
    expect(source, contains('const v12SchemaStatements'));
    expect(
      File('test/core/database/v12_app_database.g.dart').existsSync(),
      isFalse,
    );
  });
}
