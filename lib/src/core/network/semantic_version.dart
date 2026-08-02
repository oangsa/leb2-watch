final class SemanticVersion implements Comparable<SemanticVersion> {
  factory SemanticVersion.parse(String value) {
    final trimmed = value.trim();
    final match = _pattern.firstMatch(trimmed);
    if (match == null || !_validPrerelease(match.group(4))) {
      throw FormatException('Invalid semantic version.');
    }

    return SemanticVersion._(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      List.unmodifiable(match.group(4)?.split('.') ?? const <String>[]),
      match.group(5),
    );
  }

  const SemanticVersion._(
    this.major,
    this.minor,
    this.patch,
    this.prerelease,
    this.buildMetadata,
  );

  static final _pattern = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
  );

  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;
  final String? buildMetadata;

  String get coreVersion => '$major.$minor.$patch';

  @override
  int compareTo(SemanticVersion other) {
    final core = major.compareTo(other.major);
    if (core != 0) {
      return core;
    }
    final minorComparison = minor.compareTo(other.minor);
    if (minorComparison != 0) {
      return minorComparison;
    }
    final patchComparison = patch.compareTo(other.patch);
    if (patchComparison != 0) {
      return patchComparison;
    }
    if (prerelease.isEmpty && other.prerelease.isEmpty) {
      return 0;
    }
    if (prerelease.isEmpty) {
      return 1;
    }
    if (other.prerelease.isEmpty) {
      return -1;
    }

    for (var index = 0; index < prerelease.length; index++) {
      if (index >= other.prerelease.length) {
        return 1;
      }
      final left = prerelease[index];
      final right = other.prerelease[index];
      if (left == right) {
        continue;
      }
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      if (leftNumber != null) {
        return -1;
      }
      if (rightNumber != null) {
        return 1;
      }
      return left.compareTo(right);
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }

  bool operator <(SemanticVersion other) => compareTo(other) < 0;

  bool operator <=(SemanticVersion other) => compareTo(other) <= 0;

  bool operator >(SemanticVersion other) => compareTo(other) > 0;

  bool operator >=(SemanticVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is SemanticVersion && compareTo(other) == 0;

  @override
  int get hashCode =>
      Object.hash(major, minor, patch, Object.hashAll(prerelease));

  @override
  String toString() {
    final suffix = prerelease.isEmpty ? '' : '-${prerelease.join('.')}';
    final build = buildMetadata == null ? '' : '+$buildMetadata';
    return '$coreVersion$suffix$build';
  }
}

bool _validPrerelease(String? value) {
  if (value == null) {
    return true;
  }
  return value
      .split('.')
      .every((item) => item.length == 1 || !RegExp(r'^0[0-9]').hasMatch(item));
}
