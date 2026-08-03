import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/app_dependencies.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';

void main() {
  test('database close is idempotent and releases its owner once', () async {
    var releases = 0;
    final database = AppDatabase(
      NativeDatabase.memory(),
      onClose: () async {
        releases += 1;
      },
    );

    await database.close();
    await database.close();

    expect(releases, 1);
  });

  test('provider graph can await close and reopen a fresh database', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leb2-watch-provider-reset-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final storage = LocalDatabaseStorage(
      applicationSupportDirectoryProvider: () async => directory,
    );
    final container = ProviderContainer(
      overrides: [localDatabaseStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    final manager = container.read(appDatabaseManagerProvider);

    final first = await container.read(appDatabaseProvider.future);
    await manager.close();
    container.invalidate(appDatabaseProvider);
    final second = await container.read(appDatabaseProvider.future);

    expect(identical(first, second), isFalse);
    expect(await second.select(second.semesters).get(), isEmpty);
    await manager.close();
  });
}
