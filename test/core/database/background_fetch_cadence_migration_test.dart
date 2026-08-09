import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

import 'v16_app_database.dart' as v16;

void main() {
  test('upgrading adds the daytime cadence without losing intent', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-cadence-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/leb2_watch.sqlite');

    final legacy = v16.V16AppDatabase(NativeDatabase(file));
    await legacy.customStatement(
      'UPDATE background_schedule_settings '
      'SET monitoring_enabled = 1, install_jitter_seconds = 42 '
      'WHERE singleton_id = 1',
    );
    await legacy.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    expect(database.schemaVersion, 21);
    final settings = await database
        .select(database.backgroundScheduleSettings)
        .getSingle();

    expect(settings.monitoringEnabled, isTrue);
    expect(settings.installJitterSeconds, 42);
    expect(settings.daytimeCadenceMinutes, 15);
  });

  test('a fresh install starts on the default cadence', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final columns = await database
        .customSelect(
          "SELECT name FROM pragma_table_info('background_schedule_settings')",
        )
        .get();

    expect(
      columns.map((row) => row.read<String>('name')),
      contains('daytime_cadence_minutes'),
    );
    expect(
      (await database.select(database.backgroundScheduleSettings).getSingle())
          .daytimeCadenceMinutes,
      15,
    );
  });
}
