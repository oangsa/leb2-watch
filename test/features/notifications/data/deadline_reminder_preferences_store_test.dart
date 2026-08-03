import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/notifications/data/deadline_reminder_store.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_preferences.dart';

void main() {
  late AppDatabase database;
  late DriftDeadlineReminderPreferencesStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftDeadlineReminderPreferencesStore(database);
  });

  tearDown(() => database.close());

  test('watch emits committed values but not rolled-back writes', () async {
    final values = <DeadlineReminderPreferences>[];
    final subscription = store.watch().listen(values.add);
    addTearDown(subscription.cancel);
    await _settle();

    await expectLater(
      database.transaction(() async {
        await database.customStatement(
          'UPDATE deadline_reminder_preferences SET enabled = 0 '
          'WHERE singleton_id = 1',
        );
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    await _settle();

    expect(values, [DeadlineReminderPreferences.defaults]);
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}
