import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/sync/activity_identity.dart';
import 'package:leb2_watch/src/features/assignments/sync/assignment_sync_service.dart';

void main() {
  test('backend identity has priority over every fallback field', () {
    final first = resolveActivityIdentity(
      backendActivityId: 1001,
      courseId: 3001,
      activityType: 'ASM',
      title: 'Original',
      createdAtSource: '2026-07-01T09:00',
    );
    final changed = resolveActivityIdentity(
      backendActivityId: 1001,
      courseId: 9999,
      activityType: 'QUIZ',
      title: 'Changed',
      createdAtSource: '2027-01-01T00:00:00Z',
    );

    expect(first.identityKey, 'backend:1001');
    expect(changed.identityKey, first.identityKey);
    expect(first.usesFingerprint, isFalse);
  });

  test('fallback fingerprint is deterministic and versioned', () {
    final first = resolveActivityIdentity(
      backendActivityId: null,
      courseId: 3001,
      activityType: ' ASM ',
      title: '  Weekly   exercise ',
      createdAtSource: '2026-07-01T09:00',
    );
    final formattingOnly = resolveActivityIdentity(
      backendActivityId: null,
      courseId: 3001,
      activityType: 'asm',
      title: 'Weekly exercise',
      createdAtSource: '2026-07-01T09:00:00.000000000',
    );

    expect(first, isNot(same(formattingOnly)));
    expect(first.identityKey, formattingOnly.identityKey);
    expect(first.fingerprint, formattingOnly.fingerprint);
    expect(first.fingerprintVersion, activityFingerprintVersion);
    expect(
      first.fingerprint,
      'dd85f6dd199713cf61859d426076c95f593623c21c59f8803d29cdc07dcb9d9f',
    );
    expect(
      first.identityKey,
      matches(RegExp(r'^fingerprint:v1:[0-9a-f]{64}$')),
    );
  });

  test('every explicit fallback identity input contributes behaviorally', () {
    final baseline = resolveActivityIdentity(
      backendActivityId: null,
      courseId: 3001,
      activityType: 'ASM',
      title: 'Weekly exercise',
      createdAtSource: '2026-07-01T09:00',
    );
    final variations = [
      resolveActivityIdentity(
        backendActivityId: null,
        courseId: 3002,
        activityType: 'ASM',
        title: 'Weekly exercise',
        createdAtSource: '2026-07-01T09:00',
      ),
      resolveActivityIdentity(
        backendActivityId: null,
        courseId: 3001,
        activityType: 'QUIZ',
        title: 'Weekly exercise',
        createdAtSource: '2026-07-01T09:00',
      ),
      resolveActivityIdentity(
        backendActivityId: null,
        courseId: 3001,
        activityType: 'ASM',
        title: 'Different exercise',
        createdAtSource: '2026-07-01T09:00',
      ),
      resolveActivityIdentity(
        backendActivityId: null,
        courseId: 3001,
        activityType: 'ASM',
        title: 'Weekly exercise',
        createdAtSource: '2026-07-02T09:00',
      ),
    ];

    for (final variation in variations) {
      expect(variation.identityKey, isNot(baseline.identityKey));
    }
  });

  group('backend source-date canonicalization', () {
    const cases = <({String source, String canonical})>[
      (source: '+2026-07-31T23:59', canonical: '2026-07-31T23:59:00'),
      (source: '-0001-01-01T00:00', canonical: '-0001-01-01T00:00:00'),
      (source: '10000-01-01T00:00:00', canonical: '+010000-01-01T00:00:00'),
      (source: '+010000-01-01T00:00', canonical: '+010000-01-01T00:00:00'),
      (source: '2026-07-31T23:59', canonical: '2026-07-31T23:59:00'),
      (source: '2026-07-31T23:59:00', canonical: '2026-07-31T23:59:00'),
      (source: '2026-07-31T16:59:00.000Z', canonical: '2026-07-31T16:59:00Z'),
      (source: '2026-07-31T23:59:00+07:00', canonical: '2026-07-31T16:59:00Z'),
      (source: '2026-07-31T10:29:00-06:30', canonical: '2026-07-31T16:59:00Z'),
      (source: '2026-01-01T00:30:00+01:00', canonical: '2025-12-31T23:30:00Z'),
      (source: '2025-12-31T23:30:00-01:00', canonical: '2026-01-01T00:30:00Z'),
    ];

    for (final value in cases) {
      test('${value.source} becomes ${value.canonical}', () {
        expect(canonicalizeBackendDateSource(value.source), value.canonical);
      });
    }

    test('preserves all accepted fractional precisions', () {
      const digits = '123456789';
      for (var precision = 1; precision <= 9; precision++) {
        final fraction = digits.substring(0, precision);
        expect(
          canonicalizeBackendDateSource('2026-07-31T23:59:00.${fraction}Z'),
          '2026-07-31T23:59:00.${fraction}Z',
          reason: 'fractional precision $precision',
        );
      }
      expect(
        canonicalizeBackendDateSource('2026-07-31T23:59:00.120000000'),
        '2026-07-31T23:59:00.12',
      );
    });

    test('does not equate zoned and unzoned wall-clock sources', () {
      expect(
        canonicalizeBackendDateSource('2026-07-31T16:59:00'),
        isNot(canonicalizeBackendDateSource('2026-07-31T16:59:00Z')),
      );
    });

    test('returns invalid legacy values exactly and preserves null', () {
      for (final invalid in [
        'legacy date value',
        '2026-07-31 23:59:00',
        '+010000-01-01T00:00:00 UTC',
      ]) {
        expect(canonicalizeBackendDateSource(invalid), invalid);
      }
      expect(canonicalizeBackendDateSource(null), null);
    });
  });

  test('change batches are immutable, ordered, value-equal, and redacted', () {
    final batch = AssignmentChangeBatch(const [
      AssignmentChange(
        identityKey: 'backend:2',
        kind: AssignmentChangeKind.removed,
      ),
      AssignmentChange(
        identityKey: 'backend:2',
        kind: AssignmentChangeKind.newActivity,
      ),
      AssignmentChange(
        identityKey: 'backend:1',
        kind: AssignmentChangeKind.newActivity,
      ),
    ]);
    final equal = AssignmentChangeBatch(batch.changes.reversed);

    expect(batch, equal);
    expect(batch.hashCode, equal.hashCode);
    expect(
      batch.changes.map(
        (change) => '${change.kind.name}:${change.identityKey}',
      ),
      ['newActivity:backend:1', 'newActivity:backend:2', 'removed:backend:2'],
    );
    expect(
      () => batch.changes.add(
        const AssignmentChange(
          identityKey: 'backend:3',
          kind: AssignmentChangeKind.newActivity,
        ),
      ),
      throwsUnsupportedError,
    );
    expect(batch.toString(), 'AssignmentChangeBatch(redacted: true)');
    expect(batch.toString(), isNot(contains('backend:')));
  });
}
