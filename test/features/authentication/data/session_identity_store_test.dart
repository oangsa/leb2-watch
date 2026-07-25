import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/authentication/data/session_identity_store.dart';

void main() {
  late AppDatabase database;
  late DriftSessionIdentityStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftSessionIdentityStore(database);
  });

  tearDown(() => database.close());

  test('reads, saves, replaces, and deletes the singleton identity', () async {
    expect(await store.readUserId(), isNull);

    await store.saveUserId(2001);
    expect(await store.readUserId(), 2001);

    await store.saveUserId(2002);
    expect(await store.readUserId(), 2002);

    await store.deleteUserId();
    expect(await store.readUserId(), isNull);
  });

  test(
    'identity changes preserve active semester and unrelated settings',
    () async {
      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(semesterId: const drift.Value(101)),
          );
      await database
          .into(database.appSettings)
          .insert(
            const AppSettingsCompanion(
              singletonId: drift.Value(1),
              activeSemesterId: drift.Value(101),
            ),
          );

      await store.saveUserId(2001);
      var settings = await database.select(database.appSettings).getSingle();
      expect(settings.activeSemesterId, 101);
      expect(settings.leb2UserId, 2001);

      await store.deleteUserId();
      settings = await database.select(database.appSettings).getSingle();
      expect(settings.activeSemesterId, 101);
      expect(settings.leb2UserId, isNull);
    },
  );

  test(
    'rejects invalid identifiers before SQL and schema enforces the invariant',
    () async {
      for (final value in [0, -1, 2147483648]) {
        await expectLater(store.saveUserId(value), throwsArgumentError);
      }
      expect(await database.select(database.appSettings).get(), isEmpty);

      for (final value in [0, -1, 2147483648]) {
        await expectLater(
          database.customStatement(
            'INSERT OR REPLACE INTO app_settings '
            '(singleton_id, leb2_user_id) VALUES (1, ?)',
            [value],
          ),
          throwsException,
        );
      }
    },
  );

  test(
    'fixed adapter failures and debug output expose no local details',
    () async {
      await database.customStatement('DROP TABLE app_settings');

      await expectLater(
        store.readUserId(),
        throwsA(
          isA<SessionIdentityStoreException>().having(
            (error) => error.operation,
            'operation',
            SessionIdentityStoreOperation.read,
          ),
        ),
      );
      expect(store.toString(), 'DriftSessionIdentityStore(redacted: true)');
    },
  );
}
