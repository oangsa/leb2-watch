import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/sanitized_backend_fixtures.dart';

void main() {
  test('compiled semesters exactly match their JSON source', () {
    final decoded = jsonDecode(
      File(
        'test/fixtures/backend_api/semesters_success.json',
      ).readAsStringSync(),
    );

    expect(decoded, equals(sanitizedSemestersFixture));
  });

  test('compiled new-assignment snapshot exactly matches its JSON source', () {
    final decoded = jsonDecode(
      File(
        'test/fixtures/backend_api/snapshot_with_new_assignment.json',
      ).readAsStringSync(),
    );

    expect(
      decoded,
      equals(sanitizedSnapshotFixture(includeNewAssignment: true)),
    );
  });
}
