import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_preferences.dart';

void main() {
  test('defaults enable both supported deadline reminder offsets', () {
    expect(
      DeadlineReminderPreferences.defaults,
      DeadlineReminderPreferences(
        enabled: true,
        offsets: {
          DeadlineReminderOffset.oneHour,
          DeadlineReminderOffset.twentyFourHours,
        },
      ),
    );
    expect(DeadlineReminderOffset.oneHour.minutes, 60);
    expect(DeadlineReminderOffset.twentyFourHours.minutes, 1440);
  });

  test('preference values copy immutably and redact debug output', () {
    final source = <DeadlineReminderOffset>{DeadlineReminderOffset.oneHour};
    final preferences = DeadlineReminderPreferences(
      enabled: false,
      offsets: source,
    );
    source.clear();

    expect(preferences.offsets, {DeadlineReminderOffset.oneHour});
    expect(
      () => preferences.offsets.add(DeadlineReminderOffset.twentyFourHours),
      throwsUnsupportedError,
    );
    expect(
      preferences.copyWith(enabled: true),
      DeadlineReminderPreferences(
        enabled: true,
        offsets: {DeadlineReminderOffset.oneHour},
      ),
    );
    expect(preferences.toString(), contains('redacted: true'));
    expect(preferences.toString(), isNot(contains('60')));
  });

  test('either, both, or neither supported offsets are representable', () {
    for (final offsets in <Set<DeadlineReminderOffset>>[
      const {},
      const {DeadlineReminderOffset.oneHour},
      const {DeadlineReminderOffset.twentyFourHours},
      const {
        DeadlineReminderOffset.oneHour,
        DeadlineReminderOffset.twentyFourHours,
      },
    ]) {
      final value = DeadlineReminderPreferences(
        enabled: true,
        offsets: offsets,
      );
      expect(value.offsets, offsets);
    }
  });
}
