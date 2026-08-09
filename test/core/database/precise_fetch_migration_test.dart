import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

import 'v16_app_database.dart' as v16;

void main() {
  test('upgrading leaves precise checks off and the cadence intact', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-precise-fetch-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/leb2_watch.sqlite');

    final legacy = v16.V16AppDatabase(NativeDatabase(file));
    await legacy.customStatement(
      'UPDATE background_schedule_settings '
      'SET monitoring_enabled = 1 WHERE singleton_id = 1',
    );
    await legacy.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    final settings = await database
        .select(database.backgroundScheduleSettings)
        .getSingle();
    expect(settings.monitoringEnabled, isTrue);
    expect(settings.daytimeCadenceMinutes, 15);
    expect(settings.preciseFetchEnabled, isFalse);
  });

  test('the column only accepts a boolean', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await expectLater(
      database.customStatement(
        'UPDATE background_schedule_settings '
        'SET precise_fetch_enabled = 2 WHERE singleton_id = 1',
      ),
      throwsException,
    );
  });
}
