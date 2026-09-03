import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('fresh v16 schema enables new-assignment notifications', () async {
    expect(database.schemaVersion, 24);

    final preference = await database
        .select(database.newAssignmentNotificationPreferences)
        .getSingle();

    expect(preference.singletonId, 1);
    expect(preference.enabled, isTrue);
  });

  test(
    'new-assignment preference is checked and contains no secrets',
    () async {
      await expectLater(
        database.customStatement(
          'INSERT INTO new_assignment_notification_preferences '
          '(singleton_id, enabled) VALUES (2, 1)',
        ),
        throwsException,
      );

      final columns = await database
          .customSelect(
            "SELECT name FROM pragma_table_info("
            "'new_assignment_notification_preferences')",
          )
          .get();
      final names = columns
          .map((row) => row.read<String>('name').toLowerCase())
          .toList();

      expect(names, ['singleton_id', 'enabled']);
    },
  );
}
