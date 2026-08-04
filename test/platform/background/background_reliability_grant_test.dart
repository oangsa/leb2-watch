import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/background_sync/domain/desktop_autostart_service.dart';
import 'package:leb2_watch/src/platform/background/android/battery_optimization_exemption.dart';
import 'package:leb2_watch/src/platform/background/background_reliability_grant.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_background_refresh_status_bridge.dart';

void main() {
  group('android', () {
    test('maps every exemption answer, including an unreadable one', () async {
      for (final (exempt, expected) in [
        (true, BackgroundReliabilityStatus.granted),
        (false, BackgroundReliabilityStatus.notGranted),
        (null, BackgroundReliabilityStatus.unknown),
      ]) {
        final grant = AndroidBatteryOptimizationGrant(
          _Exemption(exempt: exempt),
        );

        expect(await grant.read(), expected);
      }
    });

    test('request forwards to the platform exemption', () async {
      final exemption = _Exemption(exempt: false);

      await AndroidBatteryOptimizationGrant(exemption).request();

      expect(exemption.requests, 1);
    });
  });

  group('ios', () {
    test('restricted is unknown so a blocked user is never prompted', () async {
      for (final (availability, expected) in [
        (
          IosBackgroundRefreshAvailability.available,
          BackgroundReliabilityStatus.granted,
        ),
        (
          IosBackgroundRefreshAvailability.denied,
          BackgroundReliabilityStatus.notGranted,
        ),
        (
          IosBackgroundRefreshAvailability.restricted,
          BackgroundReliabilityStatus.unknown,
        ),
        (
          IosBackgroundRefreshAvailability.unknown,
          BackgroundReliabilityStatus.unknown,
        ),
      ]) {
        final grant = IosBackgroundRefreshGrant(
          _RefreshBridge(availability: availability),
        );

        expect(await grant.read(), expected);
      }
    });

    test('a failing bridge reports unknown rather than a refusal', () async {
      final grant = IosBackgroundRefreshGrant(_RefreshBridge(fails: true));

      expect(await grant.read(), BackgroundReliabilityStatus.unknown);
    });

    test('request hands the user to the app settings screen', () async {
      final opened = <Uri>[];
      final grant = IosBackgroundRefreshGrant(_RefreshBridge(), (url) async {
        opened.add(url);
        return true;
      });

      await grant.request();

      expect(opened, [IosBackgroundRefreshGrant.settingsUrl]);
    });

    test('a failed hand-off never throws', () async {
      final grant = IosBackgroundRefreshGrant(
        _RefreshBridge(),
        (_) async => throw StateError('no settings app'),
      );

      await expectLater(grant.request(), completes);
    });
  });

  group('desktop', () {
    test('start-at-login state maps onto the grant', () async {
      for (final (support, enabled, expected) in [
        (
          DesktopAutostartSupport.available,
          true,
          BackgroundReliabilityStatus.granted,
        ),
        (
          DesktopAutostartSupport.available,
          false,
          BackgroundReliabilityStatus.notGranted,
        ),
        (
          DesktopAutostartSupport.unavailable,
          false,
          BackgroundReliabilityStatus.unknown,
        ),
        (
          DesktopAutostartSupport.unsupported,
          false,
          BackgroundReliabilityStatus.unknown,
        ),
      ]) {
        final grant = DesktopAutostartGrant(
          _Autostart(support: support, enabled: enabled),
        );

        expect(await grant.read(), expected);
      }
    });

    test('request enables start at login', () async {
      final autostart = _Autostart(
        support: DesktopAutostartSupport.available,
        enabled: false,
      );

      await DesktopAutostartGrant(autostart).request();

      expect(autostart.writes, [true]);
    });
  });

  test('an unsupported platform reports granted and never prompts', () async {
    const grant = UnsupportedBackgroundReliabilityGrant();

    expect(await grant.read(), BackgroundReliabilityStatus.granted);
    await expectLater(grant.request(), completes);
  });

  test('every grant explains itself before any system screen opens', () {
    expect(const AndroidBatteryOptimizationGrant().promptMessage, isNotEmpty);
    expect(const IosBackgroundRefreshGrant().promptMessage, isNotEmpty);
    expect(
      DesktopAutostartGrant(
        _Autostart(support: DesktopAutostartSupport.available, enabled: false),
      ).promptMessage,
      isNotEmpty,
    );
  });
}

final class _Exemption implements BatteryOptimizationExemption {
  _Exemption({required this.exempt});

  final bool? exempt;
  int requests = 0;

  @override
  Future<bool?> isExempt() async => exempt;

  @override
  Future<bool> requestExemption() async {
    requests += 1;
    return true;
  }
}

final class _RefreshBridge implements IosBackgroundRefreshStatusBridge {
  const _RefreshBridge({
    this.availability = IosBackgroundRefreshAvailability.available,
    this.fails = false,
  });

  final IosBackgroundRefreshAvailability availability;
  final bool fails;

  @override
  Future<IosBackgroundRefreshSnapshot> readStatus() async {
    if (fails) {
      throw const IosBackgroundRefreshStatusException();
    }
    return IosBackgroundRefreshSnapshot(
      availability: availability,
      pending: false,
    );
  }
}

final class _Autostart implements DesktopAutostartService {
  _Autostart({required this.support, required this.enabled});

  final DesktopAutostartSupport support;
  final bool enabled;
  final List<bool> writes = [];

  @override
  Future<void> initialize() async {}

  @override
  Stream<DesktopAutostartSnapshot> watch() => Stream.value(
    DesktopAutostartSnapshot(support: support, enabled: enabled),
  );

  @override
  Future<DesktopAutostartUpdateResult> setEnabled(bool value) async {
    writes.add(value);
    return const DesktopAutostartUpdateApplied();
  }
}
