import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/background_sync/domain/background_scheduler.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/platform/background/android/android_workmanager_scheduler_platform.dart';
import 'package:leb2_watch/src/platform/background/background_scheduler_factory.dart';
import 'package:leb2_watch/src/platform/background/desktop/desktop_background_scheduler_platform.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_workmanager_scheduler_platform.dart';
import 'package:leb2_watch/src/platform/background/unsupported_background_scheduler_platform.dart';

void main() {
  test('runtime families select their public scheduler adapters', () async {
    final expectations = <BackgroundRuntimePlatform, Matcher>{
      BackgroundRuntimePlatform.android:
          isA<AndroidWorkmanagerSchedulerPlatform>(),
      BackgroundRuntimePlatform.iOS: isA<IosWorkmanagerSchedulerPlatform>(),
      BackgroundRuntimePlatform.macOS:
          isA<DesktopBackgroundSchedulerPlatform>(),
      BackgroundRuntimePlatform.linux:
          isA<DesktopBackgroundSchedulerPlatform>(),
      BackgroundRuntimePlatform.windows:
          isA<DesktopBackgroundSchedulerPlatform>(),
      BackgroundRuntimePlatform.unsupported:
          isA<UnsupportedBackgroundSchedulerPlatform>(),
    };
    expect(
      expectations.keys,
      unorderedEquals(BackgroundRuntimePlatform.values),
    );

    for (final MapEntry(key: platform, value: matcher)
        in expectations.entries) {
      final adapter = createBackgroundSchedulerPlatform(platform);
      addTearDown(adapter.dispose);

      expect(adapter, matcher, reason: '$platform must use its public adapter');
    }

    final unsupported = createBackgroundSchedulerPlatform(
      BackgroundRuntimePlatform.unsupported,
    );
    addTearDown(unsupported.dispose);
    expect(
      await unsupported.getStatus(),
      const BackgroundScheduleUnsupported(),
    );
  });

  test('unsupported desktop autostart seam is stable and redacted', () async {
    const service = UnsupportedDesktopAutostartService();

    await service.initialize();

    expect(
      await service.watch().first,
      const DesktopAutostartSnapshot(
        support: DesktopAutostartSupport.unsupported,
        enabled: false,
      ),
    );
    expect(
      await service.setEnabled(true),
      const DesktopAutostartUpdateUnavailable(),
    );
    expect(service.toString(), contains('redacted: true'));
  });
}
