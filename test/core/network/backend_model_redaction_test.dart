import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_transport_event.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart';
import 'package:leb2_watch/src/core/network/transport/backend_dtos.dart';

import 'network_test_support.dart';

void main() {
  test('domain values have fixed redacted debug representations', () {
    const submittedAt = ActivitySubmissionTimestamp(
      date: '2026-07-01T09:00:00',
      timezoneType: 3,
      timezone: 'sensitive-timezone',
    );
    const activity = AssignmentActivity(
      semesterId: 101,
      id: 1001,
      userId: 2001,
      classId: 3001,
      advStarred: 0,
      groupType: 'sensitive-group',
      type: 'ASM',
      peerAssessment: 0,
      isAllowRepeat: 0,
      title: 'sensitive-title',
      description: 'sensitive-description',
      startDate: '2026-07-01T09:00:00',
      dueDate: '2026-07-31T23:59:00',
      editGroupMode: '',
      createdAt: '2026-06-30T12:00:00',
      user: 2001,
      activitySubmissionId: null,
      classUserId: 4001,
      activityGroupId: null,
      activityGroupName: null,
      activitySubmissionSubmittedAt: submittedAt,
      dueDateExceed: false,
      quizSubmissionIsSubmitted: false,
      countGroupMember: 1,
      activitySubmissionIsLate: false,
      fileActivitiesJson: '[]',
      questions: <int>[],
      submissionsJson: '[]',
      lastDueDateNotificationDate: null,
      lastStatusChangeNotificationDate: null,
      previousSubmissionStatus: null,
    );
    const course = Course(semesterId: 101, id: 3001, name: 'sensitive-course');

    final values = <Object>[
      const Semester(id: 101),
      course,
      CourseAssignments(course: course, activities: const [activity]),
      const AssignmentSnapshot(
        semesterId: 101,
        courses: [
          CourseAssignments(course: course, activities: [activity]),
        ],
      ),
      submittedAt,
      activity,
    ];

    for (final value in values) {
      final output = value.toString();
      expect(output, contains('redacted: true'));
      expect(output, isNot(contains('sensitive')));
      expect(output, isNot(contains('2001')));
    }
  });

  test('transport DTOs never print backend response fields', () {
    final snapshotJson =
        jsonDecode(
              File(
                'test/fixtures/backend_api/snapshot_success.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final snapshot = SemesterSnapshotDto.fromJson(snapshotJson);
    final error = StandardBackendErrorDto.fromJson(
      jsonDecode(
            File(
              'test/fixtures/backend_api/session_expired.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    ).toString();

    expect(snapshot.toString(), 'SemesterSnapshotDto(redacted: true)');
    expect(
      snapshot.classes.first.activities.first.toString(),
      'ActivityDto(redacted: true)',
    );
    expect(error, 'StandardBackendErrorDto(redacted: true)');
    expect(error, isNot(contains('SESSION_EXPIRED')));
  });

  test('failure, evidence, cancellation, and client output is safe', () {
    const evidence = BackendHttpErrorEvidence(
      statusCode: 401,
      responseCode: 'SESSION_EXPIRED',
      envelopeKind: BackendErrorEnvelopeKind.standard,
      retryAfter: Duration(seconds: 10),
      hasBearerChallenge: true,
    );
    const failure = BackendTransportException(
      kind: BackendTransportFailureKind.httpResponse,
      httpError: evidence,
    );
    final cancellation = BackendRequestCancellation();
    final adapter = CallbackHttpClientAdapter(
      (_, _, _) => jsonResponse(const <int>[]),
    );
    final client = DioBackendApiClient(
      configuration: AppConfiguration.parse(
        backendBaseUrl: 'https://example.invalid',
      ),
      credentialStore: MemoryCredentialStore(),
      httpClientAdapter: adapter,
      eventSink: (_) {},
    );

    expect(evidence.toString(), contains('redacted: true'));
    expect(evidence.toString(), isNot(contains('SESSION_EXPIRED')));
    expect(failure.toString(), contains('redacted: true'));
    expect(cancellation.toString(), contains('redacted: true'));
    expect(client.toString(), 'DioBackendApiClient(redacted: true)');
    expect(failure.toString(), isNot(contains('LEB2 session has expired')));
  });

  test('transport events include only bounded metadata', () {
    const event = BackendTransportEvent(
      method: BackendTransportMethod.get,
      route: BackendTransportRoute.semesterSnapshot,
      statusCode: 401,
      elapsed: Duration(milliseconds: 17),
      outcome: BackendTransportOutcome.httpResponse,
    );

    expect(
      event.toString(),
      'BackendTransportEvent(method: get, route: semesterSnapshot, '
      'statusCode: 401, elapsedMilliseconds: 17, outcome: httpResponse)',
    );
    expect(event.toString(), isNot(contains('/Activity/')));
    expect(event.toString(), isNot(contains('Authorization')));
  });

  test('Dio and database ownership stay behind the network module', () {
    final featureSources = Directory('lib/src/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final appSources = Directory('lib/src/app')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in [...featureSources, ...appSources]) {
      expect(file.readAsStringSync(), isNot(contains('package:dio/')));
    }

    final networkSources = Directory('lib/src/core/network')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.dart') &&
              !file.path.endsWith('.g.dart') &&
              !file.path.endsWith('.freezed.dart'),
        );
    for (final file in networkSources) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('core/database')));
      expect(source, isNot(contains('package:drift/')));
      expect(source, isNot(contains('LogInterceptor')));
    }
  });
}
