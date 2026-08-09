import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_configuration.dart';
import '../core/database/app_database.dart';
import '../core/database/local_database_storage.dart';
import '../features/background_sync/application/background_sync_runner.dart';
import '../features/background_sync/application/background_sync_task_executor.dart';
import 'app_dependencies.dart';

final class ProviderBackgroundSyncCompositionFactory
    implements BackgroundSyncCompositionFactory {
  ProviderBackgroundSyncCompositionFactory({
    AppConfiguration? configuration,
    LocalDatabaseStorage? databaseStorage,
  }) : _configuration = configuration ?? AppConfiguration.fromEnvironment(),
       _databaseStorage = databaseStorage ?? LocalDatabaseStorage();

  final AppConfiguration _configuration;
  final LocalDatabaseStorage _databaseStorage;

  @override
  Future<BackgroundSyncOwnedComposition> open() async {
    final database = await _databaseStorage.openDatabase();
    ProviderContainer? container;
    try {
      container = ProviderContainer(
        overrides: [
          appConfigurationProvider.overrideWithValue(_configuration),
          localDatabaseStorageProvider.overrideWithValue(_databaseStorage),
          appDatabaseProvider.overrideWith((_) async => database),
        ],
      );
      final runner = await container.read(backgroundSyncRunnerProvider.future);
      return _ProviderBackgroundSyncOwnedComposition(
        container,
        database,
        runner,
      );
    } on Object {
      container?.dispose();
      await database.close();
      rethrow;
    }
  }

  @override
  String toString() =>
      'ProviderBackgroundSyncCompositionFactory(redacted: true)';
}

final class _ProviderBackgroundSyncOwnedComposition
    implements BackgroundSyncOwnedComposition {
  _ProviderBackgroundSyncOwnedComposition(
    this._container,
    this._database,
    this.runner,
  );

  final ProviderContainer _container;
  final AppDatabase _database;

  @override
  final BackgroundSyncRunner runner;

  bool _closed = false;

  @override
  Future<void> checkForAppUpdate() async {
    final notifier = await _container.read(appUpdateNotifierProvider.future);
    await notifier.checkForUpdate();
  }

  @override
  Future<void> reconcileSchedule() async {
    final reconciler = await _container.read(
      backgroundScheduleReconcilerProvider.future,
    );
    await reconciler.reconcilePeriodicSync(executionAllowed: true);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _container.dispose();
    await _database.close();
  }
}
