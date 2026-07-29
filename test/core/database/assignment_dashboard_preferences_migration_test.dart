import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

import 'v13_app_database.dart' as v13;

void main() {
  test('real v13 upgrades with default dashboard preferences', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-v13-dashboard-preferences-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/leb2_watch.sqlite');

    final legacy = v13.V13AppDatabase(NativeDatabase(file));
    await legacy.customStatement(
      'INSERT INTO semesters (semester_id) VALUES (101)',
    );
    await legacy.customStatement(
      'INSERT INTO app_settings '
      '(singleton_id, active_semester_id, leb2_user_id, '
      'session_lifecycle, session_revision) '
      "VALUES (1, 101, 2001, 'active', 7)",
    );
    await legacy.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    expect(database.schemaVersion, 14);
    final preferences = await database
        .select(database.assignmentDashboardPreferencesRecords)
        .getSingle();
    expect(preferences.singletonId, 1);
    expect(preferences.section, 'all');
    expect(preferences.searchQuery, isEmpty);
    expect(preferences.selectedCourseId, isNull);
    expect(preferences.submissionFilter, 'all');
    expect(preferences.deadlineAtOrBeforeBangkok, isNull);
    final settings = await database.select(database.appSettings).getSingle();
    expect(settings.activeSemesterId, 101);
    expect(settings.leb2UserId, 2001);
    expect(settings.sessionRevision, 7);
    expect(
      await database
          .customSelect('PRAGMA user_version')
          .getSingle()
          .then((row) => row.read<int>('user_version')),
      14,
    );
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
  });

  test('v13 fixture is independent of live production tables', () {
    final source = File(
      'test/core/database/v13_app_database.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('database_tables.dart')));
    expect(source, isNot(contains('@DriftDatabase')));
    expect(source, contains('const v13SchemaStatements'));
    expect(
      File('test/core/database/v13_app_database.g.dart').existsSync(),
      isFalse,
    );
  });
}
