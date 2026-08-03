import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/authentication/data/automatic_session_reauthentication_store.dart';
import 'package:leb2_watch/src/features/authentication/domain/automatic_session_reauthentication.dart';

void main() {
  test(
    'two database connections grant one owner for an expired revision',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-automatic-reauth-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/attempt.sqlite');
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final firstDatabase = AppDatabase.forTesting(_connection(file));
      final secondDatabase = AppDatabase.forTesting(_connection(file));
      addTearDown(firstDatabase.close);
      addTearDown(secondDatabase.close);

      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      });
      await firstDatabase.select(firstDatabase.appSettings).get();
      await secondDatabase.select(secondDatabase.appSettings).get();
      await firstDatabase
          .into(firstDatabase.appSettings)
          .insert(
            const AppSettingsCompanion(
              singletonId: Value(1),
              leb2UserId: Value(2001),
              sessionLifecycle: Value('expired'),
              sessionRevision: Value(7),
            ),
          );

      final startedAt = DateTime.utc(2026, 7, 26, 12);
      final deadline = startedAt.add(const Duration(seconds: 90));
      final claims = await Future.wait([
        DriftAutomaticSessionReauthenticationStore(firstDatabase).claim(
          expectedExpiredRevision: 7,
          startedAtUtc: startedAt,
          deadlineAtUtc: deadline,
        ),
        DriftAutomaticSessionReauthenticationStore(secondDatabase).claim(
          expectedExpiredRevision: 7,
          startedAtUtc: startedAt,
          deadlineAtUtc: deadline,
        ),
      ]);

      expect(
        claims.whereType<AutomaticReauthenticationOwnerClaim>(),
        hasLength(1),
      );
      expect(
        claims.whereType<AutomaticReauthenticationJoinedClaim>(),
        hasLength(1),
      );
      expect(claims.map((claim) => claim.attempt.sessionRevision).toSet(), {7});
    },
  );

  test('active and stale revisions cannot create an attempt', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.appSettings)
        .insert(
          const AppSettingsCompanion(
            singletonId: Value(1),
            leb2UserId: Value(2001),
            sessionLifecycle: Value('active'),
            sessionRevision: Value(8),
          ),
        );
    final store = DriftAutomaticSessionReauthenticationStore(database);
    final now = DateTime.utc(2026, 7, 26, 12);

    expect(
      await store.claim(
        expectedExpiredRevision: 8,
        startedAtUtc: now,
        deadlineAtUtc: now.add(const Duration(seconds: 90)),
      ),
      isA<AutomaticReauthenticationRejectedClaim>(),
    );
    await (database.update(database.appSettings)
          ..where((row) => row.singletonId.equals(1)))
        .write(const AppSettingsCompanion(sessionLifecycle: Value('expired')));
    expect(
      await store.claim(
        expectedExpiredRevision: 7,
        startedAtUtc: now,
        deadlineAtUtc: now.add(const Duration(seconds: 90)),
      ),
      isA<AutomaticReauthenticationRejectedClaim>(),
    );
    expect(
      await database
          .select(database.automaticSessionReauthenticationAttempts)
          .get(),
      isEmpty,
    );
  });

  test('a terminal attempt is consumed and cannot be reclaimed', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedExpired(database, revision: 7);
    final store = DriftAutomaticSessionReauthenticationStore(database);
    final now = DateTime.utc(2026, 7, 26, 12);

    expect(
      await store.claim(
        expectedExpiredRevision: 7,
        startedAtUtc: now,
        deadlineAtUtc: now.add(const Duration(seconds: 90)),
      ),
      isA<AutomaticReauthenticationOwnerClaim>(),
    );
    expect(
      await store.complete(
        sessionRevision: 7,
        terminalState: AutomaticReauthenticationAttemptState.failed,
        completedAtUtc: now.add(const Duration(seconds: 1)),
        failureKind: AutomaticReauthenticationFailureKind.networkUnavailable,
      ),
      isTrue,
    );
    expect(
      await store.claim(
        expectedExpiredRevision: 7,
        startedAtUtc: now.add(const Duration(seconds: 2)),
        deadlineAtUtc: now.add(const Duration(seconds: 92)),
      ),
      isA<AutomaticReauthenticationJoinedClaim>(),
    );
    expect(
      (await store.read(7))?.failureKind,
      AutomaticReauthenticationFailureKind.networkUnavailable,
    );
  });

  test(
    'manual replacement consumes an unclaimed expired revision and cancels an owner',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedExpired(database, revision: 7);
      final store = DriftAutomaticSessionReauthenticationStore(database);
      final now = DateTime.utc(2026, 7, 26, 12);

      expect(
        await store.cancelForManualReplacement(
          expectedExpiredRevision: 7,
          completedAtUtc: now,
        ),
        isTrue,
      );
      expect(
        (await store.read(7))?.state,
        AutomaticReauthenticationAttemptState.cancelled,
      );
      expect(
        await store.claim(
          expectedExpiredRevision: 7,
          startedAtUtc: now,
          deadlineAtUtc: now.add(const Duration(seconds: 90)),
        ),
        isA<AutomaticReauthenticationJoinedClaim>(),
      );
    },
  );

  test(
    'deadline expiration is terminal and does not elect a new owner',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedExpired(database, revision: 7);
      final store = DriftAutomaticSessionReauthenticationStore(database);
      final now = DateTime.utc(2026, 7, 26, 12);
      await store.claim(
        expectedExpiredRevision: 7,
        startedAtUtc: now,
        deadlineAtUtc: now.add(const Duration(seconds: 1)),
      );

      expect(
        await store.expireDeadline(
          sessionRevision: 7,
          nowUtc: now.add(const Duration(seconds: 2)),
        ),
        isTrue,
      );
      expect(
        (await store.read(7))?.failureKind,
        AutomaticReauthenticationFailureKind.timedOut,
      );
      expect(
        await store.claim(
          expectedExpiredRevision: 7,
          startedAtUtc: now.add(const Duration(seconds: 3)),
          deadlineAtUtc: now.add(const Duration(seconds: 93)),
        ),
        isA<AutomaticReauthenticationJoinedClaim>(),
      );
    },
  );

  test(
    'claim keeps only the newest bounded terminal attempt history',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedExpired(database, revision: 99);
      final now = DateTime.utc(2026, 7, 26, 12);
      for (var revision = 0; revision < 18; revision++) {
        await database
            .into(database.automaticSessionReauthenticationAttempts)
            .insert(
              AutomaticSessionReauthenticationAttemptsCompanion.insert(
                sessionRevision: Value(revision),
                state: AutomaticReauthenticationAttemptState.failed.name,
                startedAtUtc: now,
                deadlineAtUtc: now,
                completedAtUtc: Value(now),
                failureKind: Value(
                  AutomaticReauthenticationFailureKind.networkUnavailable.name,
                ),
              ),
            );
      }
      final store = DriftAutomaticSessionReauthenticationStore(database);

      expect(
        await store.claim(
          expectedExpiredRevision: 99,
          startedAtUtc: now,
          deadlineAtUtc: now.add(const Duration(seconds: 90)),
        ),
        isA<AutomaticReauthenticationOwnerClaim>(),
      );

      final rows = await (database.select(
        database.automaticSessionReauthenticationAttempts,
      )..orderBy([(row) => OrderingTerm.asc(row.sessionRevision)])).get();
      expect(
        rows
            .where((row) => row.state != 'running')
            .map((row) => row.sessionRevision),
        List<int>.generate(16, (index) => index + 2),
      );
      expect(rows.last.sessionRevision, 99);
    },
  );

  test('attempt metadata contains no credential-shaped columns', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final rows = await database
        .customSelect(
          "SELECT name FROM pragma_table_info("
          "'automatic_session_reauthentication_attempts') ORDER BY cid",
        )
        .get();
    final columns = rows.map((row) => row.read<String>('name')).toList();
    expect(columns, [
      'session_revision',
      'state',
      'started_at_utc',
      'deadline_at_utc',
      'completed_at_utc',
      'failure_kind',
    ]);
    expect(
      columns.join(' ').toLowerCase(),
      isNot(
        anyOf(
          contains('username'),
          contains('password'),
          contains('cookie'),
          contains('authorization'),
        ),
      ),
    );
  });

  test('watch exposes the current revision without secret data', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedExpired(database, revision: 7);
    final store = DriftAutomaticSessionReauthenticationStore(database);
    final now = DateTime.utc(2026, 7, 26, 12);
    final events = <AutomaticReauthenticationAttempt?>[];
    final subscription = store.watch(7).listen(events.add);
    addTearDown(subscription.cancel);

    await store.claim(
      expectedExpiredRevision: 7,
      startedAtUtc: now,
      deadlineAtUtc: now.add(const Duration(seconds: 90)),
    );
    await store.complete(
      sessionRevision: 7,
      terminalState: AutomaticReauthenticationAttemptState.failed,
      completedAtUtc: now.add(const Duration(seconds: 1)),
      failureKind: AutomaticReauthenticationFailureKind.networkUnavailable,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      events.map((attempt) => attempt?.state),
      containsAllInOrder([
        AutomaticReauthenticationAttemptState.running,
        AutomaticReauthenticationAttemptState.failed,
      ]),
    );
    expect(events.join(' '), isNot(contains('<SESSION_COOKIE>')));
  });
}

QueryExecutor _connection(File file) {
  return NativeDatabase.createInBackground(
    file,
    readPool: 0,
    setup: (database) {
      database.execute('PRAGMA busy_timeout = 5000');
      database.execute('PRAGMA journal_mode = WAL');
    },
  );
}

Future<void> _seedExpired(AppDatabase database, {required int revision}) {
  return database
      .into(database.appSettings)
      .insert(
        AppSettingsCompanion(
          singletonId: const Value(1),
          leb2UserId: const Value(2001),
          sessionLifecycle: const Value('expired'),
          sessionRevision: Value(revision),
        ),
      );
}
