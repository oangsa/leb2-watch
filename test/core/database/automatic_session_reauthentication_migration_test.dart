import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/authentication/data/automatic_session_reauthentication_store.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';

import 'v11_app_database.dart' as v11;
import 'v14_app_database.dart' as v14;

void main() {
  test('real v11 upgrades with cached state intact and no attempt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-v11-automatic-reauth-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/leb2_watch.sqlite');

    final legacy = v11.V11AppDatabase(NativeDatabase(file));
    await legacy.customStatement(
      'INSERT INTO app_settings '
      '(singleton_id, leb2_user_id, session_lifecycle, session_revision) '
      "VALUES (1, 2001, 'expired', 7)",
    );
    await legacy.customStatement(
      'INSERT INTO semesters (semester_id) VALUES (101)',
    );
    expect(
      await legacy
          .customSelect(
            "SELECT COUNT(*) AS count FROM sqlite_master "
            "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
          )
          .getSingle()
          .then((row) => row.read<int>('count')),
      19,
    );
    await legacy.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    expect(database.schemaVersion, 24);
    expect(
      await database
          .select(database.automaticSessionReauthenticationAttempts)
          .get(),
      isEmpty,
    );
    expect(await database.select(database.semesters).get(), hasLength(1));
    final settings = await database.select(database.appSettings).getSingle();
    expect(settings.sessionLifecycle, 'expired');
    expect(settings.sessionRevision, 7);
    expect(settings.leb2UserId, 2001);
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
    expect(
      await database
          .customSelect('PRAGMA user_version')
          .getSingle()
          .then((row) => row.read<int>('user_version')),
      24,
    );
  });

  test(
    'real v14 upgrades access-key failure checks with cached state intact',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-v14-access-key-reauth-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/leb2_watch.sqlite');

      final legacy = v14.V14AppDatabase(NativeDatabase(file));
      await legacy.customStatement(
        'INSERT INTO semesters (semester_id) VALUES (46)',
      );
      await legacy.customStatement(
        'INSERT INTO courses (semester_id, course_id, name) '
        "VALUES (46, 7, 'Algorithms')",
      );
      await legacy.customStatement(
        'INSERT INTO app_settings (singleton_id) VALUES (1)',
      );
      await legacy.customStatement(
        'UPDATE app_settings SET active_semester_id = 46, '
        "leb2_user_id = 2001, session_lifecycle = 'expired', "
        'session_revision = 7 WHERE singleton_id = 1',
      );
      await legacy.customStatement(
        'INSERT INTO automatic_session_reauthentication_attempts '
        '(session_revision, state, started_at_utc, deadline_at_utc) '
        'VALUES (7, \'running\', 1000, 2000)',
      );
      await legacy.close();

      final database = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(database.close);

      expect(database.schemaVersion, 24);
      expect(await database.select(database.semesters).get(), hasLength(1));
      expect(await database.select(database.courses).get(), hasLength(1));
      final settings = await database.select(database.appSettings).getSingle();
      expect(settings.activeSemesterId, 46);
      expect(settings.leb2UserId, 2001);
      expect(settings.sessionLifecycle, 'expired');
      expect(settings.sessionRevision, 7);

      final store = DriftAutomaticSessionReauthenticationStore(database);
      expect(
        await store.complete(
          sessionRevision: 7,
          terminalState: AutomaticReauthenticationAttemptState.failed,
          completedAtUtc: DateTime.utc(2026, 8, 2),
          failureKind: AutomaticReauthenticationFailureKind.accessKeyMissing,
        ),
        isTrue,
      );
      expect(
        (await store.read(7))?.failureKind,
        AutomaticReauthenticationFailureKind.accessKeyMissing,
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test('v11 fixture is independent of live production tables', () {
    final source = File(
      'test/core/database/v11_app_database.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('database_tables.dart')));
    expect(source, isNot(contains('@DriftDatabase')));
    expect(source, contains('const v11SchemaStatements'));
    expect(
      File('test/core/database/v11_app_database.g.dart').existsSync(),
      isFalse,
    );
  });
}
