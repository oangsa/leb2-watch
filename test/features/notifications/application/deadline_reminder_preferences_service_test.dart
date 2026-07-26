import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_preferences_service.dart';
import 'package:leb2_watch/src/features/notifications/application/deadline_reminder_reconciler.dart';
import 'package:leb2_watch/src/features/notifications/data/deadline_reminder_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_preferences.dart';

void main() {
  late AppDatabase database;
  late _RecordingRequester requester;
  late LocalDeadlineReminderPreferencesService service;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    requester = _RecordingRequester();
    service = LocalDeadlineReminderPreferencesService(
      DriftDeadlineReminderPreferencesStore(database),
      requester,
    );
  });

  tearDown(() => database.close());

  test('watches seeded defaults and redacts public values', () async {
    final value = await service.watch().first;

    expect(value, DeadlineReminderPreferences.defaults);
    expect(service.toString(), contains('redacted: true'));
  });

  test('disable and re-enable preserve selected offsets', () async {
    expect(
      await service.setOffsetEnabled(
        DeadlineReminderOffset.twentyFourHours,
        enabled: false,
      ),
      isA<DeadlineReminderPreferenceUpdateSuccess>(),
    );
    expect(
      await service.setEnabled(false),
      isA<DeadlineReminderPreferenceUpdateSuccess>(),
    );
    expect(
      await service.setEnabled(true),
      isA<DeadlineReminderPreferenceUpdateSuccess>(),
    );

    final value = await service.watch().first;
    expect(value.enabled, isTrue);
    expect(value.offsets, {DeadlineReminderOffset.oneHour});
    expect(requester.calls, 3);
  });

  test('either, both, and neither offset can be persisted', () async {
    await service.setOffsetEnabled(
      DeadlineReminderOffset.oneHour,
      enabled: false,
    );
    await service.setOffsetEnabled(
      DeadlineReminderOffset.twentyFourHours,
      enabled: false,
    );
    expect((await service.watch().first).offsets, isEmpty);

    await service.setOffsetEnabled(
      DeadlineReminderOffset.twentyFourHours,
      enabled: true,
    );
    expect((await service.watch().first).offsets, {
      DeadlineReminderOffset.twentyFourHours,
    });

    await service.setOffsetEnabled(
      DeadlineReminderOffset.oneHour,
      enabled: true,
    );
    expect((await service.watch().first).offsets, {
      DeadlineReminderOffset.oneHour,
      DeadlineReminderOffset.twentyFourHours,
    });
  });

  test(
    'committed preference success survives reconciliation failure',
    () async {
      requester.failure = StateError('sensitive platform details');

      final result = await service.setEnabled(false);

      expect(result, isA<DeadlineReminderPreferenceUpdateSuccess>());
      expect((await service.watch().first).enabled, isFalse);
      expect(result.toString(), isNot(contains('sensitive')));
    },
  );

  test(
    'storage failure maps to a redacted failure without reconciliation',
    () async {
      service = LocalDeadlineReminderPreferencesService(
        const _ThrowingStore(),
        requester,
      );

      final result = await service.setEnabled(false);

      expect(result, isA<DeadlineReminderPreferenceUpdateFailure>());
      expect(result.toString(), contains('redacted: true'));
      expect(requester.calls, 0);
    },
  );

  test('watch maps storage errors to one redacted public exception', () async {
    service = LocalDeadlineReminderPreferencesService(
      const _ThrowingStore(),
      requester,
    );

    await expectLater(
      service.watch(),
      emitsError(isA<DeadlineReminderPreferencesException>()),
    );
  });
}

final class _ThrowingStore implements DeadlineReminderPreferencesStore {
  const _ThrowingStore();

  @override
  Future<void> setEnabled(bool enabled) {
    throw StateError('sensitive database detail');
  }

  @override
  Future<void> setOffsetEnabled(
    DeadlineReminderOffset offset, {
    required bool enabled,
  }) {
    throw StateError('sensitive database detail');
  }

  @override
  Stream<DeadlineReminderPreferences> watch() {
    return Stream.error(StateError('sensitive database detail'));
  }
}

final class _RecordingRequester
    implements DeadlineReminderReconciliationRequester {
  int calls = 0;
  Object? failure;

  @override
  Future<void> reconcileAfterPreferenceChange() async {
    calls += 1;
    final value = failure;
    if (value != null) {
      throw value;
    }
  }
}
