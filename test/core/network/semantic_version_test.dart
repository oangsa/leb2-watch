import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/semantic_version.dart';

void main() {
  test('compares numeric core versions without lexical ordering', () {
    expect(
      SemanticVersion.parse('0.10.0'),
      greaterThan(SemanticVersion.parse('0.9.0')),
    );
    expect(
      SemanticVersion.parse('9.0.0'),
      greaterThan(SemanticVersion.parse('0.6.0')),
    );
  });

  test('supports semver prerelease precedence and ignores build metadata', () {
    expect(
      SemanticVersion.parse('1.0.0-alpha'),
      lessThan(SemanticVersion.parse('1.0.0')),
    );
    expect(
      SemanticVersion.parse('1.0.0+1'),
      equals(SemanticVersion.parse('1.0.0+2')),
    );
    expect(
      SemanticVersion.parse('1.0.0-rc.10'),
      greaterThan(SemanticVersion.parse('1.0.0-rc.2')),
    );
  });

  test('rejects malformed versions', () {
    for (final value in ['0.5', '01.2.3', '0.5.0-', '0.5.0-alpha.01']) {
      expect(() => SemanticVersion.parse(value), throwsFormatException);
    }
  });
}
