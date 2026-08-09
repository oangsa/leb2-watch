const androidPeriodicSyncUniqueWorkName =
    'dev.oangsa.leb2watch.periodic-sync.v1';
const androidPeriodicSyncTaskName = 'leb2-periodic-sync-v1';
const androidPeriodicSyncGenerationInputKey =
    'dev.oangsa.leb2watch.periodic-sync.generation-tag-v1';
const androidPeriodicSyncGenerationTagPrefix =
    'dev.oangsa.leb2watch.periodic-sync.generation-v1.';

/// The opt-in chained task: one-off work carries no 15-minute floor and no
/// periodic flex window, so it holds the chosen cadence far more closely. Each
/// run re-arms the next link during schedule reconciliation.
const androidPreciseSyncUniqueWorkName = 'dev.oangsa.leb2watch.precise-sync.v1';
const androidPreciseSyncTaskName = 'leb2-precise-sync-v1';
const androidMinimumPeriodicCadence = Duration(minutes: 15);

/// Leaves 90 seconds for post-run work and 30 seconds for startup and teardown
/// inside WorkManager's ordinary ten-minute execution limit.
const androidBackgroundExecutionBudget = Duration(minutes: 8);

const _androidPeriodicSyncGenerationTokenLength = 32;

String formatAndroidPeriodicSyncGenerationTag(String token) {
  if (!_isLowercaseHexToken(token)) {
    throw ArgumentError(
      'must be exactly 128 bits encoded as 32 lowercase hexadecimal digits',
    );
  }
  return '$androidPeriodicSyncGenerationTagPrefix$token';
}

String? parseAndroidPeriodicSyncGenerationTag(Object? value) {
  if (value is! String ||
      !value.startsWith(androidPeriodicSyncGenerationTagPrefix)) {
    return null;
  }
  final token = value.substring(androidPeriodicSyncGenerationTagPrefix.length);
  return _isLowercaseHexToken(token) ? value : null;
}

bool _isLowercaseHexToken(String value) {
  if (value.length != _androidPeriodicSyncGenerationTokenLength) {
    return false;
  }
  for (final codeUnit in value.codeUnits) {
    final digit = codeUnit >= 0x30 && codeUnit <= 0x39;
    final lowercaseHex = codeUnit >= 0x61 && codeUnit <= 0x66;
    if (!digit && !lowercaseHex) {
      return false;
    }
  }
  return true;
}
