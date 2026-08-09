import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

import 'v15_app_database.dart' as v15;

void main() {
  test(
    'v15 to v16 preserves sync rows and stores access-key outcomes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-v15-access-key-sync-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/leb2_watch.sqlite');

      final legacy = v15.V15AppDatabase(NativeDatabase(file));
      await legacy.customStatement(
        'INSERT INTO semesters (semester_id) VALUES (46)',
      );
      await legacy.customStatement(
        'INSERT INTO courses (semester_id, course_id, name) '
        "VALUES (46, 7, 'Algorithms')",
      );
      await legacy.customStatement(
        'INSERT INTO seen_activities '
        '(semester_id, identity_key, course_id, first_seen_at_utc, '
        'last_seen_at_utc, is_baseline) '
        "VALUES (46, 'backend:1', 7, 1000, 1000, 1)",
      );
      await legacy.customStatement(
        'INSERT INTO app_settings '
        '(singleton_id, active_semester_id, leb2_user_id, session_lifecycle, '
        'session_revision) VALUES (1, 46, 2001, \'active\', 4)',
      );
      await legacy.customStatement(
        'INSERT INTO sync_operations '
        '(semester_id, user_id, reason, state, enqueued_at_utc, '
        'started_at_utc, completed_at_utc, result_failure_kind) '
        "VALUES (46, 2001, 'manualRefresh', 'failure', 1000, 1001, 1002, "
        "'networkUnavailable')",
      );
      await legacy.customStatement(
        'INSERT INTO sync_operation_changes '
        '(operation_id, semester_id, identity_key, kind) '
        "VALUES (1, 46, 'backend:1', 'newActivity')",
      );
      await legacy.customStatement(
        'INSERT INTO sync_backoff_states '
        '(semester_id, user_id, consecutive_failure_count, state, '
        'next_automatic_attempt_at_utc, last_failure_kind, updated_at_utc) '
        "VALUES (46, 2001, 1, 'waiting', 2000, 'networkUnavailable', 1002)",
      );
      await legacy.close();

      final database = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(database.close);

      expect(database.schemaVersion, 21);
      expect(
        await database.select(database.syncOperations).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.syncOperationChanges).get(),
        hasLength(1),
      );
      expect(
        (await database.select(database.syncBackoffStates).getSingle())
            .lastFailureKind,
        'networkUnavailable',
      );

      await database.customStatement(
        'INSERT INTO sync_operations '
        '(semester_id, user_id, reason, state, enqueued_at_utc, '
        'started_at_utc, completed_at_utc, result_failure_kind, '
        'result_failure_detail) '
        "VALUES (46, 2001, 'manualRefresh', 'failure', 3000, 3001, 3002, "
        "'accessKey', 'invalid')",
      );
      await database.customStatement(
        'INSERT INTO sync_backoff_states '
        '(semester_id, user_id, consecutive_failure_count, state, '
        'next_automatic_attempt_at_utc, last_failure_kind, last_failure_detail, '
        "updated_at_utc) VALUES (46, 2002, 1, 'waiting', 4000, "
        "'accessKey', 'storeUnavailable', 3002)",
      );

      await database.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);

      final operationRows = await reopened
          .select(reopened.syncOperations)
          .get();
      expect(operationRows, hasLength(2));
      final accessKeyOperation = operationRows.singleWhere(
        (row) => row.resultFailureKind == 'accessKey',
      );
      expect(accessKeyOperation.resultFailureDetail, 'invalid');
      final backoffRows = await reopened
          .select(reopened.syncBackoffStates)
          .get();
      expect(
        backoffRows.singleWhere((row) => row.userId == 2002).lastFailureDetail,
        'storeUnavailable',
      );
      expect(
        await reopened.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      final indices = await reopened
          .customSelect(
            "SELECT name FROM sqlite_schema WHERE type = 'index' "
            "AND name LIKE 'sync_%'",
          )
          .get();
      expect(
        indices.map((row) => row.read<String>('name')).toSet(),
        containsAll({
          'sync_operations_one_running',
          'sync_operations_one_active_key',
          'sync_operations_queue',
          'sync_operations_terminal_cleanup',
          'sync_operations_operation_semester',
          'sync_backoff_states_by_next_attempt',
        }),
      );
    },
  );
}
