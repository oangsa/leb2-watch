import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_schedule_store.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('every selectable cadence survives a round trip', () async {
    final store = DriftBackgroundScheduleStore(database);

    for (final cadence in BackgroundFetchCadence.values) {
      await store.setDaytimeCadence(cadence);
      expect((await store.readSettings()).daytimeCadence, cadence);
      expect((await store.watchSettings().first).daytimeCadence, cadence);
    }
  });

  test(
    'precise checks are off until asked for and survive a round trip',
    () async {
      final store = DriftBackgroundScheduleStore(database);

      expect((await store.readSettings()).preciseFetchEnabled, isFalse);

      await store.setPreciseFetchEnabled(true);
      expect((await store.readSettings()).preciseFetchEnabled, isTrue);
      expect((await store.watchSettings().first).preciseFetchEnabled, isTrue);

      await store.setPreciseFetchEnabled(false);
      expect((await store.readSettings()).preciseFetchEnabled, isFalse);
    },
  );

  test('an unselectable cadence cannot reach the column', () async {
    await expectLater(
      database.customStatement(
        'UPDATE background_schedule_settings '
        'SET daytime_cadence_minutes = 7 WHERE singleton_id = 1',
      ),
      throwsException,
    );

    expect(
      (await DriftBackgroundScheduleStore(
        database,
      ).readSettings()).daytimeCadence,
      defaultBackgroundFetchCadence,
    );
  });

  test(
    'fresh settings default monitoring off and keep one stable jitter',
    () async {
      var generated = 17;
      final store = DriftBackgroundScheduleStore(
        database,
        jitterGenerator: (_) => generated++,
      );

      expect(await store.readMonitoringEnabled(), isFalse);
      expect(await store.readOrCreateInstallJitterSeconds(), 17);
      expect(await store.readOrCreateInstallJitterSeconds(), 17);
      expect(
        await store.watchSettings().first,
        const BackgroundMonitoringSettings(
          enabled: false,
          daytimeCadence: defaultBackgroundFetchCadence,
        ),
      );
    },
  );

  test('independent database connections converge on one jitter', () async {
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    });
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-background-jitter-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = LocalDatabaseStorage(
      applicationSupportDirectoryProvider: () async => directory,
    );
    final firstDatabase = await storage.openDatabase();
    final secondDatabase = await storage.openDatabase();
    addTearDown(firstDatabase.close);
    addTearDown(secondDatabase.close);
    final first = DriftBackgroundScheduleStore(
      firstDatabase,
      jitterGenerator: (_) => 17,
    );
    final second = DriftBackgroundScheduleStore(
      secondDatabase,
      jitterGenerator: (_) => 29,
    );

    final values = await Future.wait([
      first.readOrCreateInstallJitterSeconds(),
      second.readOrCreateInstallJitterSeconds(),
    ]);

    expect(values.toSet(), hasLength(1));
    expect(values.first, anyOf(17, 29));
  });
}
