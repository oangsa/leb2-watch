final class AssignmentDetailKey {
  factory AssignmentDetailKey({
    required int semesterId,
    required String identityKey,
  }) {
    if (!_isPositiveInt32(semesterId) || !_isIdentityKey(identityKey)) {
      throw ArgumentError('Assignment detail identity is invalid.');
    }
    return AssignmentDetailKey._(
      semesterId: semesterId,
      identityKey: identityKey,
    );
  }

  const AssignmentDetailKey._({
    required this.semesterId,
    required this.identityKey,
  });

  static AssignmentDetailKey? tryParse({
    required String semesterIdSource,
    required String identityKeySource,
  }) {
    final semesterId = int.tryParse(semesterIdSource);
    if (semesterId == null ||
        !_isPositiveInt32(semesterId) ||
        !_isIdentityKey(identityKeySource)) {
      return null;
    }
    return AssignmentDetailKey._(
      semesterId: semesterId,
      identityKey: identityKeySource,
    );
  }

  final int semesterId;
  final String identityKey;

  Map<String, String> get pathParameters => Map.unmodifiable({
    'semesterId': semesterId.toString(),
    'identityKey': identityKey,
  });

  @override
  bool operator ==(Object other) =>
      other is AssignmentDetailKey &&
      other.semesterId == semesterId &&
      other.identityKey == identityKey;

  @override
  int get hashCode => Object.hash(semesterId, identityKey);

  @override
  String toString() => 'AssignmentDetailKey(redacted: true)';
}

bool _isPositiveInt32(int value) => value > 0 && value <= 2147483647;

bool _isIdentityKey(String value) {
  final backendMatch = _backendIdentity.firstMatch(value);
  if (backendMatch != null) {
    final backendId = int.tryParse(backendMatch.group(1)!);
    return backendId != null && _isPositiveInt32(backendId);
  }
  return _fingerprintIdentity.hasMatch(value);
}

final _backendIdentity = RegExp(r'^backend:([1-9]\d{0,9})$');
final _fingerprintIdentity = RegExp(r'^fingerprint:v1:[0-9a-f]{64}$');
