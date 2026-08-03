import 'dart:io';

const _maximumDurationSeconds = 9223372036854;

Duration? parseRetryAfter(String? value, {required DateTime nowUtc}) {
  if (value == null) {
    return null;
  }

  final normalized = value.trim();
  if (normalized.isEmpty) {
    return null;
  }

  if (RegExp(r'^[0-9]+$').hasMatch(normalized)) {
    final seconds = int.tryParse(normalized);
    if (seconds == null || seconds > _maximumDurationSeconds) {
      return null;
    }
    return Duration(seconds: seconds);
  }

  try {
    final retryAt = HttpDate.parse(normalized).toUtc();
    final difference = retryAt.difference(nowUtc.toUtc());
    return difference.isNegative ? Duration.zero : difference;
  } on Object {
    return null;
  }
}
