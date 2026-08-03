import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/session/session_lifecycle.dart';

void main() {
  test(
    'defaults unknown and watches durable active and expired changes',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final store = DriftSessionLifecycleStore(database);
      final iterator = StreamIterator(store.watch());
      addTearDown(iterator.cancel);

      expect(await store.read(), SessionLifecycleSnapshot.initial);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, SessionLifecycleSnapshot.initial);

      final active = await store.markVerifiedActive(userId: 2001);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, active);

      expect(
        active,
        const SessionLifecycleSnapshot(
          state: SessionLifecycleState.active,
          revision: 1,
        ),
      );
      expect(await store.markExpired(expectedRevision: 1), isTrue);
      expect(await iterator.moveNext(), isTrue);
      expect(
        iterator.current,
        const SessionLifecycleSnapshot(
          state: SessionLifecycleState.expired,
          revision: 1,
        ),
      );

      expect(
        await store.read(),
        const SessionLifecycleSnapshot(
          state: SessionLifecycleState.expired,
          revision: 1,
        ),
      );
    },
  );

  test(
    'stale expiry cannot replace a newly verified session revision',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final store = DriftSessionLifecycleStore(database);

      final first = await store.markVerifiedActive(userId: 2001);
      final replacement = await store.markVerifiedActive(userId: 2001);

      expect(
        await store.markExpired(expectedRevision: first.revision),
        isFalse,
      );
      expect(await store.read(), replacement);
      expect(replacement.state, SessionLifecycleState.active);
    },
  );

  test(
    'conditional activation advances only the exact expired revision',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final store = DriftSessionLifecycleStore(database);
      final active = await store.markVerifiedActive(userId: 2001);
      await store.markExpired(expectedRevision: active.revision);

      expect(
        await store.markVerifiedActiveIfCurrent(
          expected: const SessionLifecycleSnapshot(
            state: SessionLifecycleState.expired,
            revision: 0,
          ),
          userId: 2001,
        ),
        null,
      );
      expect(
        await store.markVerifiedActiveIfCurrent(
          expected: SessionLifecycleSnapshot(
            state: SessionLifecycleState.expired,
            revision: active.revision,
          ),
          userId: 2001,
        ),
        const SessionLifecycleSnapshot(
          state: SessionLifecycleState.active,
          revision: 2,
        ),
      );
    },
  );

  test(
    'activation clears only exact expired gates for the current user',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final store = DriftSessionLifecycleStore(database);
      final now = DateTime.utc(2026, 7, 25, 12);
      for (final semesterId in [101, 102]) {
        await database
            .into(database.semesters)
            .insert(SemestersCompanion.insert(semesterId: Value(semesterId)));
      }
      await database
          .into(database.syncBackoffStates)
          .insert(
            SyncBackoffStatesCompanion.insert(
              semesterId: 101,
              userId: 2001,
              consecutiveFailureCount: 1,
              state: 'blocked',
              lastFailureKind: 'sessionExpired',
              updatedAtUtc: now,
            ),
          );
      await database
          .into(database.syncBackoffStates)
          .insert(
            SyncBackoffStatesCompanion.insert(
              semesterId: 102,
              userId: 2001,
              consecutiveFailureCount: 1,
              state: 'blocked',
              lastFailureKind: 'invalidResponse',
              updatedAtUtc: now,
            ),
          );
      await database
          .into(database.syncBackoffStates)
          .insert(
            SyncBackoffStatesCompanion.insert(
              semesterId: 102,
              userId: 2002,
              consecutiveFailureCount: 1,
              state: 'blocked',
              lastFailureKind: 'sessionExpired',
              updatedAtUtc: now,
            ),
          );

      await store.markVerifiedActive(userId: 2001);

      final remaining = await database.select(database.syncBackoffStates).get();
      expect(
        remaining.map((row) => (row.userId, row.lastFailureKind)).toSet(),
        {(2001, 'invalidResponse'), (2002, 'sessionExpired')},
      );
    },
  );

  test('expired lifecycle survives closing and reopening SQLite', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-session-lifecycle-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/lifecycle.sqlite');

    final firstDatabase = AppDatabase.forTesting(NativeDatabase(file));
    final firstStore = DriftSessionLifecycleStore(firstDatabase);
    final active = await firstStore.markVerifiedActive(userId: 2001);
    await firstStore.markExpired(expectedRevision: active.revision);
    await firstDatabase.close();

    final reopened = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(reopened.close);
    expect(
      await DriftSessionLifecycleStore(reopened).read(),
      const SessionLifecycleSnapshot(
        state: SessionLifecycleState.expired,
        revision: 1,
      ),
    );
  });

  test('public values and failures are bounded and redacted', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const snapshot = SessionLifecycleSnapshot(
      state: SessionLifecycleState.expired,
      revision: 7,
    );
    const failure = SessionLifecycleStoreException(
      SessionLifecycleStoreOperation.expire,
    );

    expect(snapshot.toString(), 'SessionLifecycleSnapshot(redacted: true)');
    expect(failure.toString(), isNot(contains('cookie')));
    expect(failure.toString(), isNot(contains('Authorization')));
    expect(
      DriftSessionLifecycleStore(database).toString(),
      'DriftSessionLifecycleStore(redacted: true)',
    );
  });
}
