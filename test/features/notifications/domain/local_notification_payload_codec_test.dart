import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_models.dart';
import 'package:leb2_watch/src/features/notifications/domain/local_notification_payload_codec.dart';

void main() {
  const codec = LocalNotificationPayloadCodec();

  group('LocalNotificationPayloadCodec', () {
    for (final identityKey in <String>[
      'backend:456',
      'fingerprint:v1:'
          '0123456789abcdef0123456789abcdef'
          '0123456789abcdef0123456789abcdef',
    ]) {
      test('round-trips the supported $identityKey identity', () {
        final key = AssignmentDetailKey(
          semesterId: 123,
          identityKey: identityKey,
        );

        final payload = codec.encode(LocalNotificationTarget.assignment(key));

        expect(
          payload,
          '{"v":1,"type":"assignment","semesterId":123,'
          '"identityKey":"$identityKey"}',
        );
        expect(codec.decode(payload), LocalNotificationTarget.assignment(key));
        expect(utf8.encode(payload), hasLength(payload.length));
      });
    }

    test('rejects malformed and unsupported payloads without throwing', () {
      const validIdentity = 'backend:456';
      final oversized = '${' ' * 513}private';
      final invalidPayloads = <String?>[
        null,
        '',
        ' ',
        'private',
        '[]',
        '{"v":1',
        '{"v":1,"type":"assignment","semesterId":123,'
            '"identityKey":"$validIdentity"} trailing',
        '{"v":2,"type":"assignment","semesterId":123,'
            '"identityKey":"$validIdentity"}',
        '{"v":1,"type":"other","semesterId":123,'
            '"identityKey":"$validIdentity"}',
        '{"v":1,"type":"assignment","semesterId":"123",'
            '"identityKey":"$validIdentity"}',
        '{"v":1,"type":"assignment","semesterId":123.0,'
            '"identityKey":"$validIdentity"}',
        '{"v":1,"type":"assignment","semesterId":true,'
            '"identityKey":"$validIdentity"}',
        '{"v":1,"type":"assignment","semesterId":0,'
            '"identityKey":"$validIdentity"}',
        '{"v":1,"type":"assignment","semesterId":2147483648,'
            '"identityKey":"$validIdentity"}',
        '{"v":1,"type":"assignment","semesterId":123,'
            '"identityKey":"BACKEND:456"}',
        '{"v":1,"type":"assignment","semesterId":123,'
            '"identityKey":"$validIdentity","private":"value"}',
        '{"type":"assignment","semesterId":123,'
            '"identityKey":"$validIdentity"}',
        oversized,
        'é' * 257,
      ];

      for (final payload in invalidPayloads) {
        expect(
          codec.decode(payload),
          isNull,
          reason: 'payload must be invalid',
        );
      }
    });

    test('public diagnostics do not reveal payload or assignment identity', () {
      final key = AssignmentDetailKey(
        semesterId: 123,
        identityKey: 'backend:456',
      );
      final target = LocalNotificationTarget.assignment(key);

      expect(target.toString(), 'LocalNotificationTarget(redacted: true)');
      expect(codec.toString(), 'LocalNotificationPayloadCodec(redacted: true)');
      expect(target.toString(), isNot(contains('123')));
      expect(target.toString(), isNot(contains('456')));
    });
  });
}
