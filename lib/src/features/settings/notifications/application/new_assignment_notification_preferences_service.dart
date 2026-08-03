import '../data/new_assignment_notification_preferences_store.dart';
import '../domain/new_assignment_notification_settings.dart';

abstract interface class NewAssignmentNotificationPreferencesService {
  Stream<NewAssignmentNotificationSettings> watch();

  Future<NewAssignmentNotificationPreferenceUpdateResult> setEnabled(
    bool enabled,
  );
}

sealed class NewAssignmentNotificationPreferenceUpdateResult {
  const NewAssignmentNotificationPreferenceUpdateResult();

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class NewAssignmentNotificationPreferenceUpdateSuccess
    extends NewAssignmentNotificationPreferenceUpdateResult {
  const NewAssignmentNotificationPreferenceUpdateSuccess();
}

final class NewAssignmentNotificationPreferenceUpdateFailure
    extends NewAssignmentNotificationPreferenceUpdateResult {
  const NewAssignmentNotificationPreferenceUpdateFailure();
}

final class NewAssignmentNotificationPreferencesException implements Exception {
  const NewAssignmentNotificationPreferencesException();

  @override
  String toString() =>
      'NewAssignmentNotificationPreferencesException(redacted: true)';
}

final class LocalNewAssignmentNotificationPreferencesService
    implements NewAssignmentNotificationPreferencesService {
  const LocalNewAssignmentNotificationPreferencesService(this._store);

  final NewAssignmentNotificationPreferencesStore _store;

  @override
  Stream<NewAssignmentNotificationSettings> watch() {
    return _store.watch().handleError((Object _, StackTrace _) {
      throw const NewAssignmentNotificationPreferencesException();
    });
  }

  @override
  Future<NewAssignmentNotificationPreferenceUpdateResult> setEnabled(
    bool enabled,
  ) async {
    try {
      await _store.setEnabled(enabled);
      return const NewAssignmentNotificationPreferenceUpdateSuccess();
    } on Object {
      return const NewAssignmentNotificationPreferenceUpdateFailure();
    }
  }

  @override
  String toString() =>
      'LocalNewAssignmentNotificationPreferencesService(redacted: true)';
}
