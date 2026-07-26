import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/features/background_sync/data/background_schedule_store.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

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
      expect(await store.watchMonitoringEnabled().first, isFalse);
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
