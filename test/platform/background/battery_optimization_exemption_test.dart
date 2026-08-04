import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/platform/background/android/battery_optimization_exemption.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void handle(Object? Function(MethodCall call) respond) {
    messenger.setMockMethodCallHandler(
      batteryOptimizationChannel,
      (call) async => respond(call),
    );
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(batteryOptimizationChannel, null),
    );
  }

  test('reports the platform exemption status', () async {
    final calls = <String>[];
    handle((call) {
      calls.add(call.method);
      return true;
    });

    expect(
      await const AndroidBatteryOptimizationExemption().isExempt(),
      isTrue,
    );
    expect(calls, ['isExempt']);
  });

  test('an unreadable status is null rather than a false denial', () async {
    handle((_) => throw PlatformException(code: 'unavailable'));

    expect(
      await const AndroidBatteryOptimizationExemption().isExempt(),
      isNull,
    );
  });

  test('a failed request reports not launched instead of throwing', () async {
    handle((_) => throw PlatformException(code: 'unavailable'));

    expect(
      await const AndroidBatteryOptimizationExemption().requestExemption(),
      isFalse,
    );
  });

  test(
    'unsupported platforms never prompt and report themselves exempt',
    () async {
      const exemption = UnsupportedBatteryOptimizationExemption();

      expect(await exemption.isExempt(), isTrue);
      expect(await exemption.requestExemption(), isFalse);
    },
  );
}
