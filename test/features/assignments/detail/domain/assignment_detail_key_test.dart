import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';

void main() {
  test('accepts semester-scoped backend and fingerprint identities', () {
    const fingerprint =
        'fingerprint:v1:'
        '0123456789abcdef0123456789abcdef'
        '0123456789abcdef0123456789abcdef';

    expect(
      AssignmentDetailKey.tryParse(
        semesterIdSource: '101',
        identityKeySource: 'backend:1001',
      ),
      AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001'),
    );
    expect(
      AssignmentDetailKey.tryParse(
        semesterIdSource: '102',
        identityKeySource: fingerprint,
      ),
      AssignmentDetailKey(semesterId: 102, identityKey: fingerprint),
    );
  });

  test('rejects semesters outside positive int32 and malformed identities', () {
    for (final semester in ['0', '-1', '2147483648', 'one']) {
      expect(
        AssignmentDetailKey.tryParse(
          semesterIdSource: semester,
          identityKeySource: 'backend:1001',
        ),
        isNull,
      );
    }
    for (final identity in [
      '',
      'backend:0',
      'backend:-1',
      'backend:2147483648',
      'other:1001',
      'fingerprint:v1:abc',
      'fingerprint:v1:${'A' * 64}',
      'backend:1/slash',
    ]) {
      expect(
        AssignmentDetailKey.tryParse(
          semesterIdSource: '101',
          identityKeySource: identity,
        ),
        isNull,
      );
    }
  });

  test('owns equality, raw named-path parameters, and redacted debug text', () {
    final key = AssignmentDetailKey(
      semesterId: 101,
      identityKey: 'backend:1001',
    );

    expect(key.pathParameters, const {
      'semesterId': '101',
      'identityKey': 'backend:1001',
    });
    expect(
      key,
      AssignmentDetailKey(semesterId: 101, identityKey: 'backend:1001'),
    );
    expect(key.toString(), 'AssignmentDetailKey(redacted: true)');
    expect(key.toString(), isNot(contains('1001')));
  });
}
