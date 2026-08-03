import 'dart:async';

import 'package:flutter/services.dart';

import '../../../features/background_sync/application/background_sync_runner.dart';
import 'ios_background_contract.dart';

abstract interface class IosBackgroundExpirationLease
    implements BackgroundSyncCancellation {
  Future<void> close();
}

abstract interface class IosBackgroundExpirationBridge {
  Future<IosBackgroundExpirationLease> attach();
}

final class MethodChannelIosBackgroundExpirationBridge
    implements IosBackgroundExpirationBridge {
  const MethodChannelIosBackgroundExpirationBridge({
    this.attachTimeout = iosBackgroundExpirationAttachTimeout,
    this.detachTimeout = iosBackgroundExpirationDetachTimeout,
  });

  static const _channel = MethodChannel(iosBackgroundRefreshExpirationChannel);
  final Duration attachTimeout;
  final Duration detachTimeout;

  @override
  Future<IosBackgroundExpirationLease> attach() async {
    final cancellation = BackgroundSyncCancellationController();
    final bufferedGenerations = <String>{};
    String? attachedGeneration;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'expired') {
        return null;
      }
      final generation = _readEventGeneration(call.arguments);
      if (generation == null) {
        return null;
      }
      final ownedGeneration = attachedGeneration;
      if (ownedGeneration == null) {
        bufferedGenerations.add(generation);
      } else if (generation == ownedGeneration) {
        cancellation.cancel();
      }
      return null;
    });

    try {
      final response = await _channel
          .invokeMethod<Object?>('attach')
          .timeout(attachTimeout);
      final snapshot = _parseSnapshot(response);
      attachedGeneration = snapshot.generation;
      if (snapshot.expired ||
          bufferedGenerations.contains(snapshot.generation)) {
        cancellation.cancel();
      }
      bufferedGenerations.clear();
      return _MethodChannelIosBackgroundExpirationLease(
        channel: _channel,
        generation: snapshot.generation,
        cancellation: cancellation,
        detachTimeout: detachTimeout,
      );
    } on Object {
      _channel.setMethodCallHandler(null);
      throw const IosBackgroundExpirationBridgeException();
    }
  }

  @override
  String toString() =>
      'MethodChannelIosBackgroundExpirationBridge(redacted: true)';
}

final class IosBackgroundExpirationBridgeException implements Exception {
  const IosBackgroundExpirationBridgeException();

  @override
  String toString() => 'IosBackgroundExpirationBridgeException(redacted: true)';
}

final class _MethodChannelIosBackgroundExpirationLease
    implements IosBackgroundExpirationLease {
  _MethodChannelIosBackgroundExpirationLease({
    required this._channel,
    required this._generation,
    required this._cancellation,
    required this._detachTimeout,
  });

  final MethodChannel _channel;
  final String _generation;
  final BackgroundSyncCancellationController _cancellation;
  final Duration _detachTimeout;
  Future<void>? _closing;

  @override
  bool get isCancelled => _cancellation.isCancelled;

  @override
  Future<void> get whenCancelled => _cancellation.whenCancelled;

  @override
  Future<void> close() => _closing ??= _closeOnce();

  Future<void> _closeOnce() async {
    try {
      await _channel
          .invokeMethod<void>('detach', <String, Object?>{
            'generation': _generation,
          })
          .timeout(_detachTimeout);
    } on Object {
      // A later native generation supersedes this best-effort detach.
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  @override
  String toString() => 'IosBackgroundExpirationLease(redacted: true)';
}

final class _IosBackgroundExpirationSnapshot {
  const _IosBackgroundExpirationSnapshot({
    required this.generation,
    required this.expired,
  });

  final String generation;
  final bool expired;
}

_IosBackgroundExpirationSnapshot _parseSnapshot(Object? response) {
  if (response is! Map<Object?, Object?>) {
    throw const IosBackgroundExpirationBridgeException();
  }
  final generation = response['generation'];
  final expired = response['expired'];
  if (generation is! String ||
      !_isWellFormedGeneration(generation) ||
      expired is! bool) {
    throw const IosBackgroundExpirationBridgeException();
  }
  return _IosBackgroundExpirationSnapshot(
    generation: generation,
    expired: expired,
  );
}

String? _readEventGeneration(Object? arguments) {
  if (arguments is! Map<Object?, Object?>) {
    return null;
  }
  final generation = arguments['generation'];
  if (generation is! String || !_isWellFormedGeneration(generation)) {
    return null;
  }
  return generation;
}

bool _isWellFormedGeneration(String value) {
  if (value.length != 36) {
    return false;
  }
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (index == 8 || index == 13 || index == 18 || index == 23) {
      if (codeUnit != 0x2D) {
        return false;
      }
      continue;
    }
    final digit = codeUnit >= 0x30 && codeUnit <= 0x39;
    final lowercaseHex = codeUnit >= 0x61 && codeUnit <= 0x66;
    if (!digit && !lowercaseHex) {
      return false;
    }
  }
  return true;
}
