import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

import 'v16_app_database.dart' as v16;

void main() {
  test(
    'v16 to v17 adds semester names without deleting cached state',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-v16-semester-name-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/leb2_watch.sqlite');

      final legacy = v16.V16AppDatabase(NativeDatabase(file));
      await legacy.customStatement(
        'INSERT INTO semesters (semester_id) VALUES (46)',
      );
      await legacy.customStatement(
        'INSERT INTO courses (semester_id, course_id, name) '
        "VALUES (46, 7, 'Algorithms')",
      );
      await legacy.customStatement(
        'INSERT INTO app_settings '
        '(singleton_id, active_semester_id, leb2_user_id, session_lifecycle, '
        'session_revision) VALUES (1, 46, 2001, \'active\', 4)',
      );
      await legacy.close();

      final database = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(database.close);

      expect(database.schemaVersion, 19);
      final semester = await database.select(database.semesters).getSingle();
      expect(semester.semesterId, 46);
      expect(semester.name, isNull);
      expect(await database.select(database.courses).get(), hasLength(1));
      expect(
        (await database.select(database.appSettings).getSingle())
            .activeSemesterId,
        46,
      );

      await database
          .into(database.semesters)
          .insertOnConflictUpdate(
            const SemestersCompanion(
              semesterId: drift.Value(46),
              name: drift.Value('1/2026'),
            ),
          );
      expect(
        (await database.select(database.semesters).getSingle()).name,
        '1/2026',
      );
      expect(await database.select(database.courses).get(), hasLength(1));
    },
  );

  test('a legacy schema gains the reminder clock-offset column', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-v16-clock-offset-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/leb2_watch.sqlite');

    final legacy = v16.V16AppDatabase(NativeDatabase(file));
    await legacy.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    final columns = await database
        .customSelect('PRAGMA table_info(scheduled_reminders)')
        .get();
    expect(
      columns.map((column) => column.read<String>('name')),
      contains('clock_offset_microseconds'),
    );
    // Zero, because no schema this old corrected the clock at all: every alarm
    // it handed the OS was placed uncorrected.
    expect(
      columns
          .firstWhere(
            (column) =>
                column.read<String>('name') == 'clock_offset_microseconds',
          )
          .read<String>('dflt_value'),
      '0',
    );
  });
}
