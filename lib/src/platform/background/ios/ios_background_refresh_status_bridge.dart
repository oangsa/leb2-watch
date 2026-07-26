import 'package:flutter/services.dart';

const iosBackgroundRefreshStatusChannel =
    'dev.oangsa.leb2watch/background_refresh';

enum IosBackgroundRefreshAvailability { available, denied, restricted, unknown }

final class IosBackgroundRefreshSnapshot {
  const IosBackgroundRefreshSnapshot({
    required this.availability,
    required this.pending,
  });

  final IosBackgroundRefreshAvailability availability;
  final bool pending;

  @override
  bool operator ==(Object other) =>
      other is IosBackgroundRefreshSnapshot &&
      other.availability == availability &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(availability, pending);

  @override
  String toString() => 'IosBackgroundRefreshSnapshot(redacted: true)';
}

abstract interface class IosBackgroundRefreshStatusBridge {
  Future<IosBackgroundRefreshSnapshot> readStatus();
}

final class MethodChannelIosBackgroundRefreshStatusBridge
    implements IosBackgroundRefreshStatusBridge {
  const MethodChannelIosBackgroundRefreshStatusBridge();

  static const _channel = MethodChannel(iosBackgroundRefreshStatusChannel);

  @override
  Future<IosBackgroundRefreshSnapshot> readStatus() async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'getStatus',
      );
      final availability = switch (response?['backgroundRefreshStatus']) {
        'available' => IosBackgroundRefreshAvailability.available,
        'denied' => IosBackgroundRefreshAvailability.denied,
        'restricted' => IosBackgroundRefreshAvailability.restricted,
        'unknown' => IosBackgroundRefreshAvailability.unknown,
        _ => null,
      };
      final pending = response?['pending'];
      if (availability == null || pending is! bool) {
        throw const IosBackgroundRefreshStatusException();
      }
      return IosBackgroundRefreshSnapshot(
        availability: availability,
        pending: pending,
      );
    } on IosBackgroundRefreshStatusException {
      rethrow;
    } on Object {
      throw const IosBackgroundRefreshStatusException();
    }
  }

  @override
  String toString() =>
      'MethodChannelIosBackgroundRefreshStatusBridge(redacted: true)';
}

final class IosBackgroundRefreshStatusException implements Exception {
  const IosBackgroundRefreshStatusException();

  @override
  String toString() => 'IosBackgroundRefreshStatusException(redacted: true)';
}
