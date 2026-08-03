import '../data/deadline_reminder_store.dart';
import '../domain/deadline_reminder_preferences.dart';
import 'deadline_reminder_reconciler.dart';

abstract interface class DeadlineReminderPreferencesService {
  Stream<DeadlineReminderPreferences> watch();

  Future<DeadlineReminderPreferenceUpdateResult> setEnabled(bool enabled);

  Future<DeadlineReminderPreferenceUpdateResult> setOffsetEnabled(
    DeadlineReminderOffset offset, {
    required bool enabled,
  });
}

sealed class DeadlineReminderPreferenceUpdateResult {
  const DeadlineReminderPreferenceUpdateResult();

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class DeadlineReminderPreferenceUpdateSuccess
    extends DeadlineReminderPreferenceUpdateResult {
  const DeadlineReminderPreferenceUpdateSuccess();
}

final class DeadlineReminderPreferenceUpdateFailure
    extends DeadlineReminderPreferenceUpdateResult {
  const DeadlineReminderPreferenceUpdateFailure();
}

final class DeadlineReminderPreferencesException implements Exception {
  const DeadlineReminderPreferencesException();

  @override
  String toString() => 'DeadlineReminderPreferencesException(redacted: true)';
}

final class LocalDeadlineReminderPreferencesService
    implements DeadlineReminderPreferencesService {
  const LocalDeadlineReminderPreferencesService(
    this._store,
    this._reconciliationRequester, [
    this._processDeliveryRefresh,
  ]);

  final DeadlineReminderPreferencesStore _store;
  final DeadlineReminderReconciliationRequester _reconciliationRequester;
  final Future<void> Function()? _processDeliveryRefresh;

  @override
  Stream<DeadlineReminderPreferences> watch() {
    return _store.watch().handleError((Object _, StackTrace _) {
      throw const DeadlineReminderPreferencesException();
    });
  }

  @override
  Future<DeadlineReminderPreferenceUpdateResult> setEnabled(bool enabled) {
    return _update(() => _store.setEnabled(enabled));
  }

  @override
  Future<DeadlineReminderPreferenceUpdateResult> setOffsetEnabled(
    DeadlineReminderOffset offset, {
    required bool enabled,
  }) {
    return _update(() => _store.setOffsetEnabled(offset, enabled: enabled));
  }

  Future<DeadlineReminderPreferenceUpdateResult> _update(
    Future<void> Function() persist,
  ) async {
    try {
      await persist();
    } on Object {
      return const DeadlineReminderPreferenceUpdateFailure();
    }
    try {
      await _reconciliationRequester.reconcileAfterPreferenceChange();
    } on Object {
      // A committed local preference remains successful when OS work fails.
    }
    try {
      await _processDeliveryRefresh?.call();
    } on Object {
      // Durable process work is also recovered by its safety checkpoint.
    }
    return const DeadlineReminderPreferenceUpdateSuccess();
  }

  @override
  String toString() =>
      'LocalDeadlineReminderPreferencesService(redacted: true)';
}
