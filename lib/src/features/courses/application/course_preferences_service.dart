import '../data/course_preferences_store.dart';
import '../../notifications/application/deadline_reminder_reconciler.dart';

abstract interface class CoursePreferencesService {
  Stream<ActiveCourseCatalog> watchCatalog();

  Future<CoursePreferenceUpdateResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  });

  Future<CoursePreferenceUpdateResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  });
}

sealed class CoursePreferenceUpdateResult {
  const CoursePreferenceUpdateResult();
}

final class CoursePreferenceUpdateSuccess extends CoursePreferenceUpdateResult {
  const CoursePreferenceUpdateSuccess();

  @override
  String toString() => 'CoursePreferenceUpdateSuccess(redacted: true)';
}

final class CoursePreferenceUpdateStale extends CoursePreferenceUpdateResult {
  const CoursePreferenceUpdateStale();

  @override
  String toString() => 'CoursePreferenceUpdateStale(redacted: true)';
}

final class CoursePreferenceUpdateFailure extends CoursePreferenceUpdateResult {
  const CoursePreferenceUpdateFailure();

  @override
  String toString() => 'CoursePreferenceUpdateFailure(redacted: true)';
}

abstract interface class CourseEffectPolicyReader {
  Future<CourseEffectPolicy> readPolicy(CourseKey key);

  Future<Set<CourseKey>> readBackgroundMonitoredCourses(int semesterId);
}

final class CourseEffectPolicy {
  const CourseEffectPolicy({
    required this.notificationsMuted,
    required this.backgroundMonitoringEnabled,
    required this.isKnownCurrentCourse,
    required this.storageAvailable,
  });

  const CourseEffectPolicy.suppressed({
    this.notificationsMuted = true,
    this.backgroundMonitoringEnabled = false,
    this.isKnownCurrentCourse = false,
    this.storageAvailable = false,
  });

  final bool notificationsMuted;
  final bool backgroundMonitoringEnabled;
  final bool isKnownCurrentCourse;
  final bool storageAvailable;

  bool allowsNotification({required bool backgroundTriggered}) {
    return storageAvailable &&
        isKnownCurrentCourse &&
        !notificationsMuted &&
        (!backgroundTriggered || backgroundMonitoringEnabled);
  }

  bool get allowsBackgroundEffect =>
      storageAvailable && isKnownCurrentCourse && backgroundMonitoringEnabled;

  @override
  String toString() => 'CourseEffectPolicy(redacted: true)';
}

final class LocalCoursePreferencesService
    implements CoursePreferencesService, CourseEffectPolicyReader {
  LocalCoursePreferencesService(
    this._store, [
    this._deadlineReminderReconciliationRequester,
  ]);

  final CoursePreferencesStore _store;
  final DeadlineReminderReconciliationRequester?
  _deadlineReminderReconciliationRequester;

  @override
  Stream<ActiveCourseCatalog> watchCatalog() => _store.watchActiveCatalog();

  @override
  Future<CoursePreferenceUpdateResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  }) async {
    final result = await _update(
      () => _store.setNotificationsMuted(key, muted: muted),
    );
    final requester = _deadlineReminderReconciliationRequester;
    if (result is CoursePreferenceUpdateSuccess && requester != null) {
      try {
        await requester.reconcileAfterPreferenceChange();
      } on Object {
        // The committed course preference remains the authoritative result.
      }
    }
    return result;
  }

  @override
  Future<CoursePreferenceUpdateResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  }) {
    return _update(
      () => _store.setBackgroundMonitoringEnabled(key, enabled: enabled),
    );
  }

  @override
  Future<CourseEffectPolicy> readPolicy(CourseKey key) async {
    try {
      final preference = await _store.readCurrentCoursePreference(key);
      if (preference == null) {
        return const CourseEffectPolicy.suppressed(storageAvailable: true);
      }
      return CourseEffectPolicy(
        notificationsMuted: preference.notificationsMuted,
        backgroundMonitoringEnabled: preference.backgroundMonitoringEnabled,
        isKnownCurrentCourse: true,
        storageAvailable: true,
      );
    } on Object {
      return const CourseEffectPolicy.suppressed();
    }
  }

  @override
  Future<Set<CourseKey>> readBackgroundMonitoredCourses(int semesterId) async {
    try {
      return await _store.readBackgroundMonitoredCourses(semesterId);
    } on Object {
      return const <CourseKey>{};
    }
  }

  Future<CoursePreferenceUpdateResult> _update(
    Future<CoursePreferenceWriteResult> Function() action,
  ) async {
    try {
      return switch (await action()) {
        CoursePreferenceWriteApplied() => const CoursePreferenceUpdateSuccess(),
        CoursePreferenceWriteStale() => const CoursePreferenceUpdateStale(),
      };
    } on Object {
      return const CoursePreferenceUpdateFailure();
    }
  }

  @override
  String toString() => 'LocalCoursePreferencesService(redacted: true)';
}
