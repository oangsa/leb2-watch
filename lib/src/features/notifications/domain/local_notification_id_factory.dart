import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'local_notification_models.dart';

final class LocalNotificationIdFactory {
  const LocalNotificationIdFactory();

  static const int testNotificationId = localNotificationTestId;

  String canonicalOwnerKey(NotificationOwner owner) {
    final assignment = owner.assignment;
    return switch (owner.kind) {
      NotificationKind.newAssignment =>
        'leb2-notification:v1:new:'
            '${assignment.semesterId}:${assignment.identityKey}',
      NotificationKind.deadlineReminder =>
        'leb2-notification:v1:deadline:'
            '${assignment.semesterId}:${assignment.identityKey}:'
            '${owner.offsetMinutes}',
    };
  }

  Iterable<LocalNotificationId> candidates(NotificationOwner owner) sync* {
    for (var probe = 0; probe <= 2147483647; probe += 1) {
      final digest = sha256.convert(
        utf8.encode('${canonicalOwnerKey(owner)}\u0000$probe'),
      );
      final bytes = digest.bytes;
      final word =
          ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) &
          0x7fffffff;
      if (word == 0 || word == testNotificationId) {
        continue;
      }
      yield LocalNotificationId(value: word, owner: owner);
    }
  }

  @override
  String toString() => 'LocalNotificationIdFactory(redacted: true)';
}
