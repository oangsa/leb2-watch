import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

import 'v10_app_database.dart' as v10;

void main() {
  test(
    'real v10 upgrades with terminal history intact and empty outbox',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-v10-outbox-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/leb2_watch.sqlite');

      final legacy = v10.V10AppDatabase(NativeDatabase(file));
      await legacy.customStatement(
        'INSERT INTO semesters (semester_id) VALUES (101)',
      );
      await legacy.customStatement(
        'INSERT INTO seen_activities '
        '(semester_id, identity_key, course_id, first_seen_at_utc, '
        'last_seen_at_utc, is_baseline) VALUES (?, ?, ?, ?, ?, ?)',
        [
          101,
          'backend:1001',
          3001,
          DateTime.utc(2026, 7, 25).millisecondsSinceEpoch,
          DateTime.utc(2026, 7, 26).millisecondsSinceEpoch,
          0,
        ],
      );
      await legacy.customStatement(
        'INSERT INTO notification_history '
        '(dedupe_key, semester_id, identity_key, kind, notification_id, '
        'recorded_at_utc) VALUES (?, ?, ?, ?, ?, ?)',
        [
          'leb2-notification:v1:new:101:backend:1001',
          101,
          'backend:1001',
          'new-assignment',
          7001,
          DateTime.utc(2026, 7, 26).millisecondsSinceEpoch,
        ],
      );
      expect(
        await legacy
            .customSelect(
              "SELECT COUNT(*) AS count FROM sqlite_master "
              "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .getSingle()
            .then((row) => row.read<int>('count')),
        18,
      );
      await legacy.close();

      final database = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(database.close);

      expect(database.schemaVersion, 17);
      expect(
        await database.select(database.notificationHistory).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.newAssignmentNotificationOutbox).get(),
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

  test('v10 fixture is independent of live production tables', () {
    final source = File(
      'test/core/database/v10_app_database.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('database_tables.dart')));
    expect(source, isNot(contains('@DriftDatabase')));
    expect(source, contains('const v10SchemaStatements'));
    expect(
      File('test/core/database/v10_app_database.g.dart').existsSync(),
      isFalse,
    );
  });
}
