import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

import 'v16_app_database.dart' as v16;

void main() {
  test('upgrading keeps app settings and announces nothing yet', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-app-update-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/leb2_watch.sqlite');

    final legacy = v16.V16AppDatabase(NativeDatabase(file));
    await legacy.customStatement(
      'INSERT INTO app_settings (singleton_id, leb2_user_id) VALUES (1, 4242)',
    );
    await legacy.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    final settings = await database.select(database.appSettings).getSingle();
    expect(settings.leb2UserId, 4242);
    expect(settings.notifiedUpdateVersion, isNull);
    expect(settings.updateCheckedAtUtc, isNull);
  });

  test('a fresh install carries the update notification columns', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final columns = await database
        .customSelect("SELECT name FROM pragma_table_info('app_settings')")
        .get();

    expect(
      columns.map((row) => row.read<String>('name')),
      containsAll(['notified_update_version', 'update_checked_at_utc']),
    );
  });
}
