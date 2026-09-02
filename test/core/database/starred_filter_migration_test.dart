import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

import 'v16_app_database.dart' as v16;

void main() {
  test('upgrading adds the starred filter without changing saved '
      'filters', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-starred-filter-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/leb2_watch.sqlite');

    final legacy = v16.V16AppDatabase(NativeDatabase(file));
    await legacy.customStatement(
      'UPDATE assignment_dashboard_preferences '
      "SET section = 'overdue', search_query = 'graph', "
      "selected_course_id = 3001, submission_filter = 'all', "
      "deadline_at_or_before_bangkok = '2026-08-01T10:30' "
      'WHERE singleton_id = 1',
    );
    await legacy.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    final preferences = await database
        .select(database.assignmentDashboardPreferencesRecords)
        .getSingle();
    expect(preferences.starredFilter, 'all');
    expect(preferences.section, 'overdue');
    expect(preferences.searchQuery, 'graph');
    expect(preferences.selectedCourseId, 3001);
    expect(preferences.submissionFilter, 'all');
    expect(preferences.deadlineAtOrBeforeBangkok, '2026-08-01T10:30');
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
  });

  test('the column only accepts the two known filters', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database.customStatement(
      'UPDATE assignment_dashboard_preferences '
      "SET starred_filter = 'starred' WHERE singleton_id = 1",
    );
    await expectLater(
      database.customStatement(
        'UPDATE assignment_dashboard_preferences '
        "SET starred_filter = 'unrecognised' WHERE singleton_id = 1",
      ),
      throwsException,
    );
  });
}
