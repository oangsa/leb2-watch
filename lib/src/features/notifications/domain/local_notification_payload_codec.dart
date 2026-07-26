import 'dart:convert';

import '../../assignments/detail/domain/assignment_detail_key.dart';
import 'local_notification_models.dart';

final class LocalNotificationPayloadCodec {
  const LocalNotificationPayloadCodec();

  static const int maximumPayloadLength = 512;

  String encode(LocalNotificationTarget target) {
    final key = switch (target) {
      AssignmentNotificationTarget(:final key) => key,
    };
    return jsonEncode(<String, Object>{
      'v': 1,
      'type': 'assignment',
      'semesterId': key.semesterId,
      'identityKey': key.identityKey,
    });
  }

  LocalNotificationTarget? decode(String? payload) {
    if (payload == null ||
        payload.isEmpty ||
        payload.length > maximumPayloadLength ||
        utf8.encode(payload).length > maximumPayloadLength) {
      return null;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 4 ||
          !decoded.keys.toSet().containsAll(const <String>{
            'v',
            'type',
            'semesterId',
            'identityKey',
          }) ||
          decoded['v'] != 1 ||
          decoded['type'] != 'assignment' ||
          decoded['semesterId'] is! int ||
          decoded['identityKey'] is! String) {
        return null;
      }

      final key = AssignmentDetailKey.tryParse(
        semesterIdSource: (decoded['semesterId'] as int).toString(),
        identityKeySource: decoded['identityKey'] as String,
      );
      return key == null ? null : LocalNotificationTarget.assignment(key);
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'LocalNotificationPayloadCodec(redacted: true)';
}
