import 'dart:io';

import 'package:flutter/services.dart';

/// Android battery-optimization allowlist state for this app.
///
/// Doze defers periodic WorkManager runs far past their cadence while the app
/// is optimized, so the exemption is what makes background sync land close to
/// its schedule. Every value is best effort: the platform may refuse to
/// report or to prompt, and the user may decline.
abstract interface class BatteryOptimizationExemption {
  /// Whether background work is currently exempt from battery optimization.
  ///
  /// Returns `null` when the platform cannot report a status, so callers do
  /// not treat "unknown" as "denied".
  Future<bool?> isExempt();

  /// Shows the system exemption prompt and reports whether it was launched.
  ///
  /// The prompt's outcome is only observable through a later [isExempt] read.
  Future<bool> requestExemption();
}

const batteryOptimizationChannel = MethodChannel(
  'dev.oangsa.leb2watch/battery-optimization',
);

final class AndroidBatteryOptimizationExemption
    implements BatteryOptimizationExemption {
  const AndroidBatteryOptimizationExemption([
    this._channel = batteryOptimizationChannel,
  ]);

  final MethodChannel _channel;

  @override
  Future<bool?> isExempt() async {
    try {
      return await _channel.invokeMethod<bool>('isExempt');
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> requestExemption() async {
    try {
      return await _channel.invokeMethod<bool>('requestExemption') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  String toString() => 'AndroidBatteryOptimizationExemption(redacted: true)';
}

/// Every non-Android platform reports itself as already exempt so shared
/// callers never surface an Android-only prompt.
final class UnsupportedBatteryOptimizationExemption
    implements BatteryOptimizationExemption {
  const UnsupportedBatteryOptimizationExemption();

  @override
  Future<bool?> isExempt() async => true;

  @override
  Future<bool> requestExemption() async => false;

  @override
  String toString() => 'UnsupportedBatteryOptimizationExemption()';
}

BatteryOptimizationExemption createBatteryOptimizationExemption() {
  return Platform.isAndroid
      ? const AndroidBatteryOptimizationExemption()
      : const UnsupportedBatteryOptimizationExemption();
}
