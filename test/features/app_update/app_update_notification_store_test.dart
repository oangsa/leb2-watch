import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/app_update/app_update_notification_store.dart';

void main() {
  late AppDatabase database;
  late DriftAppUpdateNotificationStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftAppUpdateNotificationStore(database);
  });

  tearDown(() => database.close());

  test('a fresh install has announced nothing', () async {
    final state = await store.read();

    expect(state.notifiedVersion, isNull);
    expect(state.checkedAtUtc, isNull);
  });

  test('records the announced release and the last check', () async {
    final checkedAt = DateTime.utc(2026, 8, 9, 12);

    await store.recordNotified('0.8.0');
    await store.recordChecked(checkedAt);

    final state = await store.read();
    expect(state.notifiedVersion, '0.8.0');
    expect(state.checkedAtUtc, checkedAt);
  });

  test('keeps existing settings when the row already exists', () async {
    await database.customStatement(
      'INSERT INTO app_settings (singleton_id, leb2_user_id) VALUES (1, 77)',
    );

    await store.recordNotified('0.8.0');

    final settings = await database.select(database.appSettings).getSingle();
    expect(settings.leb2UserId, 77);
    expect(settings.notifiedUpdateVersion, '0.8.0');
  });

  test('rejects a blank release version', () async {
    expect(() => store.recordNotified('  '), throwsArgumentError);
  });
}
