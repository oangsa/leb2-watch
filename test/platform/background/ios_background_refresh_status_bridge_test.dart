import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/platform/background/ios/ios_background_refresh_status_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(iosBackgroundRefreshStatusChannel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reads available pending status without a next execution claim',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getStatus');
            return <String, Object?>{
              'backgroundRefreshStatus': 'available',
              'pending': true,
            };
          });

      final snapshot =
          await const MethodChannelIosBackgroundRefreshStatusBridge()
              .readStatus();

      expect(
        snapshot,
        const IosBackgroundRefreshSnapshot(
          availability: IosBackgroundRefreshAvailability.available,
          pending: true,
        ),
      );
    },
  );

  test('preserves denied and restricted availability', () async {
    for (final entry in const {
      'denied': IosBackgroundRefreshAvailability.denied,
      'restricted': IosBackgroundRefreshAvailability.restricted,
    }.entries) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            return <String, Object?>{
              'backgroundRefreshStatus': entry.key,
              'pending': false,
            };
          });

      expect(
        (await const MethodChannelIosBackgroundRefreshStatusBridge()
                .readStatus())
            .availability,
        entry.value,
      );
    }
  });

  test('maps malformed native responses to one redacted failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object?>{
            'backgroundRefreshStatus': 'PRIVATE_NATIVE_VALUE',
            'pending': 'yes',
          };
        });

    await expectLater(
      const MethodChannelIosBackgroundRefreshStatusBridge().readStatus(),
      throwsA(
        isA<IosBackgroundRefreshStatusException>().having(
          (error) => error.toString(),
          'redaction',
          isNot(contains('PRIVATE_NATIVE_VALUE')),
        ),
      ),
    );
  });
}
