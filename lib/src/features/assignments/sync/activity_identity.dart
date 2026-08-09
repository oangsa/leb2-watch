import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/time/app_time_zone.dart';

const activityFingerprintVersion = 1;

final class ResolvedActivityIdentity {
  const ResolvedActivityIdentity._({
    required this.identityKey,
    this.fingerprintVersion,
    this.fingerprint,
  });

  factory ResolvedActivityIdentity.backend(int backendActivityId) {
    if (backendActivityId <= 0 || backendActivityId > 2147483647) {
      throw ArgumentError.value(
        backendActivityId,
        'backendActivityId',
        'must be a positive int32',
      );
    }
    return ResolvedActivityIdentity._(
      identityKey: 'backend:$backendActivityId',
    );
  }

  factory ResolvedActivityIdentity.fingerprint({
    required int courseId,
    required String activityType,
    required String title,
    required String createdAtSource,
  }) {
    final fields = [
      courseId.toString(),
      _normalizeWhitespace(activityType).toLowerCase(),
      _normalizeWhitespace(title),
      canonicalizeBackendDateSource(createdAtSource)!,
    ];
    final canonical = StringBuffer('v$activityFingerprintVersion');
    for (final field in fields) {
      final bytes = utf8.encode(field);
      canonical
        ..write(':')
        ..write(bytes.length)
        ..write(':')
        ..write(field);
    }
    final digest = sha256.convert(utf8.encode(canonical.toString())).toString();
    return ResolvedActivityIdentity._(
      identityKey: 'fingerprint:v$activityFingerprintVersion:$digest',
      fingerprintVersion: activityFingerprintVersion,
      fingerprint: digest,
    );
  }

  final String identityKey;
  final int? fingerprintVersion;
  final String? fingerprint;

  bool get usesFingerprint => fingerprint != null;
}

ResolvedActivityIdentity resolveActivityIdentity({
  required int? backendActivityId,
  required int courseId,
  required String activityType,
  required String title,
  required String createdAtSource,
}) {
  if (backendActivityId != null) {
    return ResolvedActivityIdentity.backend(backendActivityId);
  }
  return ResolvedActivityIdentity.fingerprint(
    courseId: courseId,
    activityType: activityType,
    title: title,
    createdAtSource: createdAtSource,
  );
}

final _backendDatePattern = RegExp(
  r'^([+-]?\d{4,6})-(\d{2})-(\d{2})T(\d{2}):(\d{2})'
  r'(?::(\d{2})(?:\.(\d{1,9}))?)?'
  r'(Z|[+-]\d{2}:\d{2})?$',
);

/// Canonicalizes verified backend date syntax without assigning a timezone to
/// an unzoned source. Unknown legacy values are returned unchanged.
String? canonicalizeBackendDateSource(String? source) {
  if (source == null) {
    return null;
  }
  final match = _backendDatePattern.firstMatch(source);
  final parsed = DateTime.tryParse(source);
  if (match == null || parsed == null) {
    return source;
  }

  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6] ?? '0');
  final fraction = _canonicalFraction(match[7]);
  final zone = match[8];
  final local = DateTime.utc(year, month, day, hour, minute, second);

  if (zone == null) {
    return '${_year(local.year)}-${_two(local.month)}-${_two(local.day)}'
        'T${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}'
        '$fraction';
  }

  final utc = parsed.toUtc();
  return '${_year(utc.year)}-${_two(utc.month)}-${_two(utc.day)}'
      'T${_two(utc.hour)}:${_two(utc.minute)}:${_two(utc.second)}${fraction}Z';
}

/// Resolves a backend date source to the UTC instant it names, so a legacy
/// unzoned wall clock cached before the backend started sending offsets
/// compares equal to its zoned replacement when both name the same instant.
/// Sources [canonicalizeBackendDateSource] can't parse fall back to its
/// (opaque) output, so unparsable values still compare without throwing.
Object? resolveBackendDateInstant(String? source) {
  final canonical = canonicalizeBackendDateSource(source);
  if (canonical == null) {
    return null;
  }
  final isZoned = canonical.endsWith('Z');
  final wallClockUtc = DateTime.tryParse(isZoned ? canonical : '${canonical}Z');
  if (wallClockUtc == null) {
    return canonical;
  }
  return isZoned ? wallClockUtc : appTimeZone.instantAt(wallClockUtc);
}

String _normalizeWhitespace(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

String _canonicalFraction(String? source) {
  if (source == null) {
    return '';
  }
  final trimmed = source.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.isEmpty ? '' : '.$trimmed';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _year(int value) {
  final absolute = value.abs();
  if (value >= -9999 && value <= 9999) {
    final sign = value < 0 ? '-' : '';
    return '$sign${absolute.toString().padLeft(4, '0')}';
  }
  final sign = value < 0 ? '-' : '+';
  return '$sign${absolute.toString().padLeft(6, '0')}';
}
