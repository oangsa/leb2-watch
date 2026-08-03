import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/settings/notifications/application/new_assignment_notification_preferences_service.dart';
import 'package:leb2_watch/src/features/settings/notifications/data/new_assignment_notification_preferences_store.dart';
import 'package:leb2_watch/src/features/settings/notifications/domain/new_assignment_notification_settings.dart';

void main() {
  test('maps saved values and persists one requested update', () async {
    final store = _PreferencesStore();
    final service = LocalNewAssignmentNotificationPreferencesService(store);

    expect(
      await service.watch().first,
      const NewAssignmentNotificationSettings(enabled: true),
    );
    expect(
      await service.setEnabled(false),
      isA<NewAssignmentNotificationPreferenceUpdateSuccess>(),
    );
    expect(store.writes, [false]);
  });

  test('maps storage failures without exposing the source error', () async {
    final store = _PreferencesStore(failWrites: true);
    final service = LocalNewAssignmentNotificationPreferencesService(store);

    final result = await service.setEnabled(false);

    expect(result, isA<NewAssignmentNotificationPreferenceUpdateFailure>());
    expect(result.toString(), isNot(contains('<PRIVATE_STORAGE_ERROR>')));
    expect(service.toString(), isNot(contains('<PRIVATE_STORAGE_ERROR>')));
  });
}

final class _PreferencesStore
    implements NewAssignmentNotificationPreferencesStore {
  _PreferencesStore({this.failWrites = false});

  final bool failWrites;
  final List<bool> writes = [];

  @override
  Stream<NewAssignmentNotificationSettings> watch() =>
      Stream.value(const NewAssignmentNotificationSettings(enabled: true));

  @override
  Future<void> setEnabled(bool enabled) async {
    writes.add(enabled);
    if (failWrites) {
      throw StateError('<PRIVATE_STORAGE_ERROR>');
    }
  }
}
