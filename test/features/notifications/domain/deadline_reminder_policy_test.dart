import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/notifications/data/local_notifications_platform.dart';
import 'package:leb2_watch/src/features/notifications/domain/deadline_reminder_policy.dart';

void main() {
  test('iOS policy owns the nearest sixty-four app reminders', () {
    expect(
      DeadlineReminderSchedulingPolicy.iOS,
      const DeadlineReminderSchedulingPolicy(
        supportsScheduling: true,
        supportsCancellation: true,
        maximumPendingCount: 64,
      ),
    );
  });

  test('platform policies distinguish cleanup from scheduling support', () {
    expect(DeadlineReminderSchedulingPolicy.android.maximumPendingCount, null);
    expect(DeadlineReminderSchedulingPolicy.macOS.maximumPendingCount, null);
    expect(
      DeadlineReminderSchedulingPolicy.windowsPackaged.maximumPendingCount,
      null,
    );
    expect(DeadlineReminderSchedulingPolicy.linux.supportsScheduling, isFalse);
    expect(DeadlineReminderSchedulingPolicy.linux.supportsCancellation, isTrue);
    expect(
      DeadlineReminderSchedulingPolicy.windowsUnpackaged.supportsCancellation,
      isFalse,
    );
    expect(
      DeadlineReminderSchedulingPolicy.unsupported.supportsScheduling,
      isFalse,
    );
  });

  test('invalid caps are rejected and debug output is redacted', () {
    expect(
      () => DeadlineReminderSchedulingPolicy(
        supportsScheduling: true,
        supportsCancellation: true,
        maximumPendingCount: 0,
      ),
      throwsAssertionError,
    );
    expect(
      DeadlineReminderSchedulingPolicy.iOS.toString(),
      'DeadlineReminderSchedulingPolicy(redacted: true)',
    );
  });

  test('application-owned runtime capabilities map without plugin types', () {
    expect(
      LocalNotificationPlatformCapabilities.forPlatform(
        NotificationRuntimePlatform.iOS,
      ).deadlineReminderPolicy,
      DeadlineReminderSchedulingPolicy.iOS,
    );
    expect(
      LocalNotificationPlatformCapabilities.forPlatform(
        NotificationRuntimePlatform.windows,
      ).deadlineReminderPolicy,
      DeadlineReminderSchedulingPolicy.windowsUnpackaged,
    );
    expect(
      LocalNotificationPlatformCapabilities.forPlatform(
        NotificationRuntimePlatform.windows,
        windowsPackaged: true,
      ).deadlineReminderPolicy,
      DeadlineReminderSchedulingPolicy.windowsPackaged,
    );
  });
}
