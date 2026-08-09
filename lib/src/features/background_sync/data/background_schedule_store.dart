import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/background_scheduler.dart';

const maximumBackgroundInstallJitterSeconds = 300;

enum BackgroundScheduleStoreOperation {
  read,
  watch,
  writeMonitoring,
  writeCadence,
  createJitter,
}

final class BackgroundScheduleStoreException implements Exception {
  const BackgroundScheduleStoreException(this.operation);

  final BackgroundScheduleStoreOperation operation;

  @override
  String toString() =>
      'BackgroundScheduleStoreException('
      'operation: ${operation.name}, redacted: true)';
}

abstract interface class BackgroundScheduleStore {
  Future<bool> readMonitoringEnabled();

  Future<BackgroundMonitoringSettings> readSettings();

  Stream<BackgroundMonitoringSettings> watchSettings();

  Future<void> setMonitoringEnabled(bool enabled);

  Future<void> setDaytimeCadence(BackgroundFetchCadence cadence);

  Future<void> setPreciseFetchEnabled(bool enabled);

  Future<int> readOrCreateInstallJitterSeconds();
}

final class DriftBackgroundScheduleStore implements BackgroundScheduleStore {
  DriftBackgroundScheduleStore(
    this._database, {
    int Function(int maxExclusive)? jitterGenerator,
  }) : _jitterGenerator = jitterGenerator ?? Random.secure().nextInt;

  final AppDatabase _database;
  final int Function(int maxExclusive) _jitterGenerator;

  @override
  Future<bool> readMonitoringEnabled() {
    return _run(
      BackgroundScheduleStoreOperation.read,
      () async => (await _readSettings()).monitoringEnabled,
    );
  }

  @override
  Future<BackgroundMonitoringSettings> readSettings() {
    return _run(
      BackgroundScheduleStoreOperation.read,
      () async => _settingsOf(await _readSettings()),
    );
  }

  @override
  Stream<BackgroundMonitoringSettings> watchSettings() async* {
    try {
      await for (final row
          in _database
              .select(_database.backgroundScheduleSettings)
              .watchSingle()) {
        yield _settingsOf(row);
      }
    } on Object {
      throw const BackgroundScheduleStoreException(
        BackgroundScheduleStoreOperation.watch,
      );
    }
  }

  @override
  Future<void> setMonitoringEnabled(bool enabled) {
    return _run(BackgroundScheduleStoreOperation.writeMonitoring, () async {
      final updated =
          await (_database.update(
            _database.backgroundScheduleSettings,
          )..where((row) => row.singletonId.equals(1))).write(
            BackgroundScheduleSettingsCompanion(
              monitoringEnabled: Value(enabled),
            ),
          );
      if (updated != 1) {
        throw StateError('Background schedule settings are unavailable.');
      }
    });
  }

  @override
  Future<void> setDaytimeCadence(BackgroundFetchCadence cadence) {
    return _run(BackgroundScheduleStoreOperation.writeCadence, () async {
      final updated =
          await (_database.update(
            _database.backgroundScheduleSettings,
          )..where((row) => row.singletonId.equals(1))).write(
            BackgroundScheduleSettingsCompanion(
              daytimeCadenceMinutes: Value(cadence.minutes),
            ),
          );
      if (updated != 1) {
        throw StateError('Background schedule settings are unavailable.');
      }
    });
  }

  @override
  Future<void> setPreciseFetchEnabled(bool enabled) {
    return _run(BackgroundScheduleStoreOperation.writeCadence, () async {
      final updated =
          await (_database.update(
            _database.backgroundScheduleSettings,
          )..where((row) => row.singletonId.equals(1))).write(
            BackgroundScheduleSettingsCompanion(
              preciseFetchEnabled: Value(enabled),
            ),
          );
      if (updated != 1) {
        throw StateError('Background schedule settings are unavailable.');
      }
    });
  }

  @override
  Future<int> readOrCreateInstallJitterSeconds() {
    return _run(BackgroundScheduleStoreOperation.createJitter, () async {
      final candidate = _jitterGenerator(
        maximumBackgroundInstallJitterSeconds + 1,
      );
      if (candidate < 0 || candidate > maximumBackgroundInstallJitterSeconds) {
        throw StateError('The generated background jitter is invalid.');
      }
      await _database.customUpdate(
        'UPDATE background_schedule_settings '
        'SET install_jitter_seconds = ? '
        'WHERE singleton_id = 1 AND install_jitter_seconds IS NULL',
        variables: [Variable<int>(candidate)],
        updates: {_database.backgroundScheduleSettings},
      );
      final stored = (await _readSettings()).installJitterSeconds;
      if (stored == null ||
          stored < 0 ||
          stored > maximumBackgroundInstallJitterSeconds) {
        throw StateError('Background schedule jitter is unavailable.');
      }
      return stored;
    });
  }

  Future<BackgroundScheduleSetting> _readSettings() {
    return _database.select(_database.backgroundScheduleSettings).getSingle();
  }

  BackgroundMonitoringSettings _settingsOf(BackgroundScheduleSetting row) {
    return BackgroundMonitoringSettings(
      enabled: row.monitoringEnabled,
      daytimeCadence:
          BackgroundFetchCadence.fromMinutes(row.daytimeCadenceMinutes) ??
          defaultBackgroundFetchCadence,
      preciseFetchEnabled: row.preciseFetchEnabled,
    );
  }

  Future<T> _run<T>(
    BackgroundScheduleStoreOperation operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on ArgumentError {
      rethrow;
    } on Object {
      throw BackgroundScheduleStoreException(operation);
    }
  }

  @override
  String toString() => 'DriftBackgroundScheduleStore(redacted: true)';
}
