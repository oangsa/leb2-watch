import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_background_contract.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_background_expiration_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(iosBackgroundRefreshExpirationChannel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  test('attach returns one uncancelled redacted lease', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'attach');
      expect(call.arguments, isNull);
      return <String, Object?>{'generation': _generationA, 'expired': false};
    });

    final lease = await const MethodChannelIosBackgroundExpirationBridge()
        .attach();

    expect(lease.isCancelled, isFalse);
    expect(lease.toString(), isNot(contains(_generationA)));
    await lease.close();
  });

  test('latched expiration cancels before attach completes', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'attach') {
        return <String, Object?>{'generation': _generationA, 'expired': true};
      }
      return null;
    });

    final lease = await const MethodChannelIosBackgroundExpirationBridge()
        .attach();

    expect(lease.isCancelled, isTrue);
    await lease.whenCancelled;
    await lease.close();
  });

  test('live matching expiration cancels once', () async {
    var detachCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'attach') {
        return <String, Object?>{'generation': _generationA, 'expired': false};
      }
      detachCalls += 1;
      return null;
    });
    final lease = await const MethodChannelIosBackgroundExpirationBridge()
        .attach();

    await _sendExpired(channel, _generationA);
    await _sendExpired(channel, _generationA);

    expect(lease.isCancelled, isTrue);
    await lease.close();
    expect(detachCalls, 1);
  });

  test('expiration arriving before attach reply is buffered', () async {
    final attachReply = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (call) {
      if (call.method == 'attach') {
        return attachReply.future;
      }
      return Future<Object?>.value();
    });
    final attaching = const MethodChannelIosBackgroundExpirationBridge()
        .attach();

    await _sendExpired(channel, _generationA);
    attachReply.complete(<String, Object?>{
      'generation': _generationA,
      'expired': false,
    });
    final lease = await attaching;

    expect(lease.isCancelled, isTrue);
    await lease.close();
  });

  test(
    'malformed and stale events cannot cancel the owned generation',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'attach') {
          return <String, Object?>{
            'generation': _generationB,
            'expired': false,
          };
        }
        return null;
      });
      final lease = await const MethodChannelIosBackgroundExpirationBridge()
          .attach();

      await _sendNativeCall(
        channel,
        const MethodCall('expired', <String, Object?>{'generation': 'PRIVATE'}),
      );
      await _sendExpired(channel, _generationA);

      expect(lease.isCancelled, isFalse);
      await _sendExpired(channel, _generationB);
      expect(lease.isCancelled, isTrue);
      await lease.close();
    },
  );

  test('malformed attach response fails closed with redacted error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      return <String, Object?>{
        'generation': 'PRIVATE_NATIVE_PAYLOAD',
        'expired': 'yes',
      };
    });

    await expectLater(
      const MethodChannelIosBackgroundExpirationBridge().attach(),
      throwsA(
        isA<IosBackgroundExpirationBridgeException>().having(
          (error) => error.toString(),
          'redaction',
          allOf(
            isNot(contains('PRIVATE_NATIVE_PAYLOAD')),
            contains('redacted'),
          ),
        ),
      ),
    );
  });

  test('attach failure and timeout are bounded redacted failures', () async {
    for (final handler in <Future<Object?> Function(MethodCall)>[
      (_) => Future<Object?>.error(StateError('PRIVATE_PLATFORM_DETAIL')),
      (_) => Completer<Object?>().future,
    ]) {
      messenger.setMockMethodCallHandler(channel, handler);
      final bridge = MethodChannelIosBackgroundExpirationBridge(
        attachTimeout: Duration.zero,
      );

      await expectLater(
        bridge.attach(),
        throwsA(
          isA<IosBackgroundExpirationBridgeException>().having(
            (error) => error.toString(),
            'redaction',
            isNot(contains('PRIVATE_PLATFORM_DETAIL')),
          ),
        ),
      );
    }
  });

  test('close sends exact generation once and removes the handler', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'attach') {
        return <String, Object?>{'generation': _generationA, 'expired': false};
      }
      return null;
    });
    final lease = await const MethodChannelIosBackgroundExpirationBridge()
        .attach();

    await lease.close();
    await lease.close();
    await _sendExpired(channel, _generationA);

    expect(calls.map((call) => call.method), <String>['attach', 'detach']);
    expect(calls.last.arguments, <String, Object?>{'generation': _generationA});
    expect(lease.isCancelled, isFalse);
  });

  test('detach failure and timeout cannot make close unbounded', () async {
    for (final handler in <Future<Object?> Function(MethodCall)>[
      (call) => call.method == 'attach'
          ? Future<Object?>.value(<String, Object?>{
              'generation': _generationA,
              'expired': false,
            })
          : Future<Object?>.error(StateError('PRIVATE_DETACH_DETAIL')),
      (call) => call.method == 'attach'
          ? Future<Object?>.value(<String, Object?>{
              'generation': _generationA,
              'expired': false,
            })
          : Completer<Object?>().future,
    ]) {
      messenger.setMockMethodCallHandler(channel, handler);
      final lease = await MethodChannelIosBackgroundExpirationBridge(
        detachTimeout: Duration.zero,
      ).attach();

      await lease.close();
      expect(lease.toString(), isNot(contains('PRIVATE_DETACH_DETAIL')));
    }
  });
}

const _generationA = '11111111-1111-4111-8111-111111111111';
const _generationB = '22222222-2222-4222-8222-222222222222';

Future<void> _sendExpired(MethodChannel channel, String generation) {
  return _sendNativeCall(
    channel,
    MethodCall('expired', <String, Object?>{'generation': generation}),
  );
}

Future<void> _sendNativeCall(MethodChannel channel, MethodCall call) {
  final completer = Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(call),
        (_) => completer.complete(),
      );
  return completer.future;
}
