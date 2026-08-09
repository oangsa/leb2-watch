import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'local_notification_models.dart';

final class LocalNotificationIdFactory {
  const LocalNotificationIdFactory();

  static const int testNotificationId = localNotificationTestId;
  static const int appUpdateNotificationId = localNotificationAppUpdateId;

  String canonicalOwnerKey(NotificationOwner owner) {
    final assignment = owner.assignment;
    return switch (owner.kind) {
      NotificationKind.newAssignment => newAssignmentOwnerKey(
        semesterId: assignment.semesterId,
        identityKey: assignment.identityKey,
      ),
      NotificationKind.deadlineReminder =>
        'leb2-notification:v1:deadline:'
            '${assignment.semesterId}:${assignment.identityKey}:'
            '${owner.offsetMinutes}',
    };
  }

  String newAssignmentOwnerKey({
    required int semesterId,
    required String identityKey,
  }) {
    if (semesterId <= 0 ||
        semesterId > 2147483647 ||
        identityKey.trim().isEmpty) {
      throw ArgumentError('Notification owner identity is invalid.');
    }
    return 'leb2-notification:v1:new:$semesterId:$identityKey';
  }

  Iterable<int> candidateValuesForOwnerKey(String ownerKey) sync* {
    if (ownerKey.trim().isEmpty) {
      throw ArgumentError('Notification owner key is invalid.');
    }
    for (var probe = 0; probe <= 2147483647; probe += 1) {
      final digest = sha256.convert(utf8.encode('$ownerKey\u0000$probe'));
      final bytes = digest.bytes;
      final word =
          ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) &
          0x7fffffff;
      if (word == 0 ||
          word == testNotificationId ||
          word == appUpdateNotificationId) {
        continue;
      }
      yield word;
    }
  }

  Iterable<LocalNotificationId> candidates(NotificationOwner owner) sync* {
    for (final value in candidateValuesForOwnerKey(canonicalOwnerKey(owner))) {
      yield LocalNotificationId(value: value, owner: owner);
    }
  }

  @override
  String toString() => 'LocalNotificationIdFactory(redacted: true)';
}
