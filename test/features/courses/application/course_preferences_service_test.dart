import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/courses/application/course_preferences_service.dart';
import 'package:leb2_watch/src/features/courses/data/course_preferences_store.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_reconciler.dart';

void main() {
  const key = CourseKey(semesterId: 101, courseId: 3001);

  test('maps applied, stale, and failed writes to bounded results', () async {
    final store = _FakeCoursePreferencesStore()
      ..preference = const CoursePreference();
    final service = LocalCoursePreferencesService(store);

    store.writeResult = const CoursePreferenceWriteApplied();
    expect(
      await service.setNotificationsMuted(key, muted: true),
      isA<CoursePreferenceUpdateSuccess>(),
    );
    store.writeResult = const CoursePreferenceWriteStale();
    expect(
      await service.setBackgroundMonitoringEnabled(key, enabled: false),
      isA<CoursePreferenceUpdateStale>(),
    );
    store.failure = StateError('sensitive storage failure');
    expect(
      await service.setNotificationsMuted(key, muted: false),
      isA<CoursePreferenceUpdateFailure>(),
    );
    expect(service.toString(), 'LocalCoursePreferencesService(redacted: true)');
  });

  test(
    'policy defaults allow foreground and background notifications',
    () async {
      final store = _FakeCoursePreferencesStore()
        ..preference = const CoursePreference();
      final service = LocalCoursePreferencesService(store);

      final policy = await service.readPolicy(key);

      expect(policy.storageAvailable, isTrue);
      expect(policy.isKnownCurrentCourse, isTrue);
      expect(policy.allowsNotification(backgroundTriggered: false), isTrue);
      expect(policy.allowsNotification(backgroundTriggered: true), isTrue);
      expect(policy.allowsBackgroundEffect, isTrue);
      expect(policy.toString(), 'CourseEffectPolicy(redacted: true)');
    },
  );

  test('mute and background controls remain independent', () async {
    final store = _FakeCoursePreferencesStore();
    final service = LocalCoursePreferencesService(store);

    store.preference = const CoursePreference(notificationsMuted: true);
    var policy = await service.readPolicy(key);
    expect(policy.allowsNotification(backgroundTriggered: false), isFalse);
    expect(policy.allowsBackgroundEffect, isTrue);

    store.preference = const CoursePreference(
      backgroundMonitoringEnabled: false,
    );
    policy = await service.readPolicy(key);
    expect(policy.allowsNotification(backgroundTriggered: false), isTrue);
    expect(policy.allowsNotification(backgroundTriggered: true), isFalse);
    expect(policy.allowsBackgroundEffect, isFalse);
  });

  test('global course controls gate every course policy', () async {
    final store = _FakeCoursePreferencesStore()
      ..preference = const CoursePreference();
    final service = LocalCoursePreferencesService(store);

    store.globalPreference = const CourseGlobalPreference(
      notificationsMuted: true,
    );
    var policy = await service.readPolicy(key);
    expect(policy.allowsNotification(backgroundTriggered: false), isFalse);
    expect(policy.allowsBackgroundEffect, isTrue);

    store.globalPreference = const CourseGlobalPreference(
      backgroundMonitoringEnabled: false,
    );
    policy = await service.readPolicy(key);
    expect(policy.allowsNotification(backgroundTriggered: false), isTrue);
    expect(policy.allowsNotification(backgroundTriggered: true), isFalse);
    expect(policy.allowsBackgroundEffect, isFalse);
  });

  test('unknown course and storage errors fail closed', () async {
    final store = _FakeCoursePreferencesStore();
    final service = LocalCoursePreferencesService(store);

    var policy = await service.readPolicy(key);
    expect(policy.storageAvailable, isTrue);
    expect(policy.isKnownCurrentCourse, isFalse);
    expect(policy.notificationsMuted, isTrue);
    expect(policy.backgroundMonitoringEnabled, isFalse);
    expect(policy.allowsNotification(backgroundTriggered: false), isFalse);

    store.failure = StateError('sensitive');
    policy = await service.readPolicy(key);
    expect(policy.storageAvailable, isFalse);
    expect(policy.allowsBackgroundEffect, isFalse);
    expect(await service.readBackgroundMonitoredCourses(101), isEmpty);
  });

  test('background monitored keys are immutable and forwarded', () async {
    final store = _FakeCoursePreferencesStore()..backgroundKeys = {key};
    final service = LocalCoursePreferencesService(store);

    final keys = await service.readBackgroundMonitoredCourses(101);

    expect(keys, {key});
    expect(() => keys.add(key), throwsUnsupportedError);
  });

  test(
    'committed notification mute requests reconciliation only for mute',
    () async {
      final store = _FakeCoursePreferencesStore();
      final requester = _RecordingReminderRequester();
      var processRefreshes = 0;
      final service = LocalCoursePreferencesService(store, requester, () async {
        processRefreshes += 1;
      });

      expect(
        await service.setNotificationsMuted(key, muted: true),
        isA<CoursePreferenceUpdateSuccess>(),
      );
      expect(requester.calls, 1);
      expect(processRefreshes, 1);

      expect(
        await service.setBackgroundMonitoringEnabled(key, enabled: false),
        isA<CoursePreferenceUpdateSuccess>(),
      );
      expect(requester.calls, 1);
      expect(processRefreshes, 1);
    },
  );

  test('mute success survives reminder reconciliation failure', () async {
    final store = _FakeCoursePreferencesStore();
    final requester = _RecordingReminderRequester()
      ..failure = StateError('sensitive platform detail');
    final service = LocalCoursePreferencesService(store, requester);

    final result = await service.setNotificationsMuted(key, muted: true);

    expect(result, isA<CoursePreferenceUpdateSuccess>());
    expect(result.toString(), isNot(contains('sensitive')));
    expect(requester.calls, 1);
  });
}

final class _RecordingReminderRequester
    implements DeadlineReminderReconciliationRequester {
  int calls = 0;
  Object? failure;

  @override
  Future<void> reconcileAfterPreferenceChange() async {
    calls += 1;
    final current = failure;
    if (current != null) {
      throw current;
    }
  }
}

final class _FakeCoursePreferencesStore implements CoursePreferencesStore {
  CoursePreferenceWriteResult writeResult =
      const CoursePreferenceWriteApplied();
  CoursePreference? preference;
  CourseGlobalPreference globalPreference = const CourseGlobalPreference();
  Set<CourseKey> backgroundKeys = const {};
  Object? failure;

  void _throwIfNeeded() {
    final current = failure;
    if (current != null) {
      throw current;
    }
  }

  @override
  Future<ActiveCourseCatalog> readActiveCatalog() async {
    _throwIfNeeded();
    return ActiveCourseCatalog(activeSemesterId: null, courses: const []);
  }

  @override
  Stream<CourseGlobalPreference> watchGlobalPreference() =>
      Stream.value(globalPreference);

  @override
  Future<CourseGlobalPreference> readGlobalPreference() async {
    _throwIfNeeded();
    return globalPreference;
  }

  @override
  Future<Set<CourseKey>> readBackgroundMonitoredCourses(int semesterId) async {
    _throwIfNeeded();
    return Set.unmodifiable(backgroundKeys);
  }

  @override
  Future<CoursePreference?> readCurrentCoursePreference(CourseKey key) async {
    _throwIfNeeded();
    return preference;
  }

  @override
  Future<CoursePreferenceWriteResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  }) async {
    _throwIfNeeded();
    return writeResult;
  }

  @override
  Future<CoursePreferenceWriteResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  }) async {
    _throwIfNeeded();
    return writeResult;
  }

  @override
  Future<CoursePreferenceWriteResult> setGlobalNotificationsMuted({
    required bool muted,
  }) async {
    _throwIfNeeded();
    return writeResult;
  }

  @override
  Future<CoursePreferenceWriteResult> setGlobalBackgroundMonitoringEnabled({
    required bool enabled,
  }) async {
    _throwIfNeeded();
    return writeResult;
  }

  @override
  Stream<ActiveCourseCatalog> watchActiveCatalog() async* {
    _throwIfNeeded();
    yield ActiveCourseCatalog(activeSemesterId: null, courses: const []);
  }
}
