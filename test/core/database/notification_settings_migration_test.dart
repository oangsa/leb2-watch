import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

import 'v9_app_database.dart' as v9;

void main() {
  test('migrates real v9 settings and seeds notifications enabled', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-v9-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/leb2_watch.sqlite');

    final legacy = v9.V9AppDatabase(NativeDatabase(file));
    await legacy
        .update(legacy.backgroundScheduleSettings)
        .write(
          const v9.BackgroundScheduleSettingsCompanion(
            monitoringEnabled: Value(true),
            installJitterSeconds: Value(42),
          ),
        );
    expect(
      await legacy
          .select(legacy.backgroundScheduleSettings)
          .getSingle()
          .then((row) => row.monitoringEnabled),
      isTrue,
    );
    await legacy.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    expect(
      await database
          .select(database.newAssignmentNotificationPreferences)
          .getSingle()
          .then((row) => row.enabled),
      isTrue,
    );
    final background = await database
        .select(database.backgroundScheduleSettings)
        .getSingle();
    expect(background.monitoringEnabled, isTrue);
    expect(background.installJitterSeconds, 42);
    expect(
      await database
          .customSelect('PRAGMA user_version')
          .getSingle()
          .then((row) => row.read<int>('user_version')),
      10,
    );
  });
}
