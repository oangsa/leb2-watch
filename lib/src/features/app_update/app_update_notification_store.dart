import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';

/// What the app already announced about newer releases.
final class AppUpdateNotificationState {
  const AppUpdateNotificationState({
    required this.notifiedVersion,
    required this.checkedAtUtc,
  });

  /// The release the notification was last posted for, or `null` when none has
  /// been posted on this install.
  final String? notifiedVersion;

  /// When background work last asked the backend for release metadata.
  final DateTime? checkedAtUtc;

  @override
  String toString() => 'AppUpdateNotificationState(redacted: true)';
}

abstract interface class AppUpdateNotificationStore {
  Future<AppUpdateNotificationState> read();

  Future<void> recordChecked(DateTime nowUtc);

  Future<void> recordNotified(String version);
}

final class DriftAppUpdateNotificationStore
    implements AppUpdateNotificationStore {
  const DriftAppUpdateNotificationStore(this._database);

  final AppDatabase _database;

  @override
  Future<AppUpdateNotificationState> read() async {
    // The settings row is created lazily by the first session or semester
    // write, so an install that has never signed in has no row at all.
    final row = await _database.select(_database.appSettings).getSingleOrNull();
    return AppUpdateNotificationState(
      notifiedVersion: row?.notifiedUpdateVersion,
      checkedAtUtc: row?.updateCheckedAtUtc,
    );
  }

  @override
  Future<void> recordChecked(DateTime nowUtc) {
    return _write(
      AppSettingsCompanion(updateCheckedAtUtc: Value(nowUtc.toUtc())),
    );
  }

  @override
  Future<void> recordNotified(String version) {
    if (version.trim().isEmpty) {
      throw ArgumentError('The announced release version is invalid.');
    }
    return _write(
      AppSettingsCompanion(notifiedUpdateVersion: Value(version.trim())),
    );
  }

  Future<void> _write(AppSettingsCompanion values) {
    return _database.transaction(() async {
      final updated = await (_database.update(
        _database.appSettings,
      )..where((row) => row.singletonId.equals(1))).write(values);
      if (updated == 1) {
        return;
      }
      await _database
          .into(_database.appSettings)
          .insert(
            values.copyWith(singletonId: const Value(1)),
            mode: InsertMode.insertOrIgnore,
          );
      final stored = await _database
          .select(_database.appSettings)
          .getSingleOrNull();
      if (stored == null) {
        throw StateError('App settings are unavailable.');
      }
    });
  }

  @override
  String toString() => 'DriftAppUpdateNotificationStore(redacted: true)';
}
