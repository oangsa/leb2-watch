import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/app/provider_background_sync_composition.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/core/database/local_database_access_gate.dart';
import 'package:leb2_watch/src/core/database/local_database_storage.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';

void main() {
  test(
    'headless sync uses its injected storage for activity admission',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leb2-watch-headless-storage-identity-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final storage = _TrackingStorage(directory);
      final seed = await storage.openDatabase();
      await seed
          .into(seed.semesters)
          .insert(SemestersCompanion.insert(semesterId: const Value(101)));
      await seed
          .into(seed.appSettings)
          .insertOnConflictUpdate(
            const AppSettingsCompanion(
              singletonId: Value(1),
              activeSemesterId: Value(101),
              leb2UserId: Value(2001),
              sessionLifecycle: Value('active'),
              sessionRevision: Value(1),
            ),
          );
      await seed.close();

      final owned = await ProviderBackgroundSyncCompositionFactory(
        configuration: AppConfiguration.parse(
          backendBaseUrl: 'http://127.0.0.1:1/',
        ),
        databaseStorage: storage,
      ).open();
      addTearDown(owned.close);

      await owned.runner.run(reason: SyncReason.manualRefresh);

      expect(storage.activityLeaseCalls, 1);
    },
  );
}

final class _TrackingStorage extends LocalDatabaseStorage {
  _TrackingStorage(this.directory)
    : super(applicationSupportDirectoryProvider: () async => directory);

  final Directory directory;
  int activityLeaseCalls = 0;

  @override
  Future<LocalDataActivityLease> acquireActivityLease() {
    activityLeaseCalls += 1;
    return super.acquireActivityLease();
  }
}
