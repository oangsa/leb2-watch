import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart';
import 'package:leb2_watch/src/core/network/domain/learning_material_models.dart';
import 'package:leb2_watch/src/features/assignments/attachments/application/attachment_download_service.dart';
import 'package:leb2_watch/src/features/assignments/attachments/domain/attachment_download.dart';
import 'package:leb2_watch/src/features/assignments/detail/application/assignment_detail_service.dart';
import 'package:leb2_watch/src/features/assignments/detail/domain/assignment_detail_key.dart';

void main() {
  test('saves one attachment under the name the backend supplied', () async {
    final client = _FakeClient();
    final sink = _RecordingSink();
    final service = AttachmentDownloadService(() => client, sink);

    final result = await service.downloadOne(
      detail: _detail(),
      attachmentId: 33,
    );

    expect(result, isA<AttachmentDownloadSaved>());
    final saved = result as AttachmentDownloadSaved;
    expect(saved.fileName, 'lab4.pdf');
    expect(saved.path, '/saved/lab4.pdf');
    expect(sink.writes.single.fileName, 'lab4.pdf');
    expect(client.attachmentCalls.single, (
      semesterId: 101,
      classId: 11,
      activityId: 4001,
      attachmentId: 33,
      userId: 2001,
    ));
  });

  test('downloads every attachment as one archive request', () async {
    final client = _FakeClient();
    final service = AttachmentDownloadService(() => client, _RecordingSink());

    await service.downloadAll(detail: _detail(attachmentIds: const [33, 34]));

    expect(client.archiveCalls, hasLength(1));
    expect(client.attachmentCalls, isEmpty);
  });

  test('refuses an activity that has no backend id to address', () async {
    final client = _FakeClient();
    final service = AttachmentDownloadService(() => client, _RecordingSink());

    final result = await service.downloadOne(
      detail: _detail(backendActivityId: null),
      attachmentId: 33,
    );

    expect(
      result,
      isA<AttachmentDownloadFailed>().having(
        (failure) => failure.reason,
        'reason',
        AttachmentDownloadFailureReason.unsupportedActivity,
      ),
    );
    expect(client.attachmentCalls, isEmpty);
  });

  test('reports an expired session distinctly from other failures', () async {
    final client = _FakeClient()
      ..failure = const BackendTransportException(
        kind: BackendTransportFailureKind.httpResponse,
        httpError: BackendHttpErrorEvidence(
          statusCode: 401,
          responseCode: 'SESSION_EXPIRED',
          envelopeKind: BackendErrorEnvelopeKind.standard,
          hasBearerChallenge: true,
        ),
      );
    final service = AttachmentDownloadService(() => client, _RecordingSink());

    final result = await service.downloadOne(
      detail: _detail(),
      attachmentId: 33,
    );

    expect(
      result,
      isA<AttachmentDownloadFailed>().having(
        (failure) => failure.reason,
        'reason',
        AttachmentDownloadFailureReason.sessionExpired,
      ),
    );
  });

  test('a transport failure never reaches storage', () async {
    final client = _FakeClient()
      ..failure = const BackendTransportException(
        kind: BackendTransportFailureKind.connectionError,
      );
    final sink = _RecordingSink();
    final service = AttachmentDownloadService(() => client, sink);

    final result = await service.downloadOne(
      detail: _detail(),
      attachmentId: 33,
    );

    expect(
      result,
      isA<AttachmentDownloadFailed>().having(
        (failure) => failure.reason,
        'reason',
        AttachmentDownloadFailureReason.unavailable,
      ),
    );
    expect(sink.writes, isEmpty);
  });

  test('a failed write is reported as a storage failure', () async {
    final sink = _RecordingSink()..shouldThrow = true;
    final client = _FakeClient();
    final service = AttachmentDownloadService(() => client, sink);

    final result = await service.downloadOne(
      detail: _detail(),
      attachmentId: 33,
    );

    expect(
      result,
      isA<AttachmentDownloadFailed>().having(
        (failure) => failure.reason,
        'reason',
        AttachmentDownloadFailureReason.storageFailed,
      ),
    );
  });

  test(
    'saves a learning-material file through the shared download flow',
    () async {
      final learningClient = _FakeLearningClient();
      final sink = _RecordingSink();
      final service = AttachmentDownloadService(
        () => _FakeClient(),
        sink,
        learningActivityClient: () => learningClient,
      );

      final result = await service.downloadLearningMaterialOne(
        semesterId: 101,
        classId: 11,
        materialId: 5001,
        attachmentId: 6001,
        userId: 2001,
      );

      expect(result, isA<AttachmentDownloadSaved>());
      expect(sink.writes.single.fileName, 'reading.pdf');
      expect(learningClient.attachmentCalls.single, (
        semesterId: 101,
        classId: 11,
        materialId: 5001,
        attachmentId: 6001,
        userId: 2001,
      ));
    },
  );

  test('downloads all learning-material files as one archive', () async {
    final learningClient = _FakeLearningClient();
    final service = AttachmentDownloadService(
      () => _FakeClient(),
      _RecordingSink(),
      learningActivityClient: () => learningClient,
    );

    final result = await service.downloadLearningMaterialAll(
      semesterId: 101,
      classId: 11,
      materialId: 5001,
      userId: 2001,
    );

    expect(result, isA<AttachmentDownloadSaved>());
    expect(learningClient.archiveCalls.single, (
      semesterId: 101,
      classId: 11,
      materialId: 5001,
      userId: 2001,
    ));
  });
}

CurrentAssignmentDetail _detail({
  int? backendActivityId = 4001,
  List<int> attachmentIds = const [33],
}) {
  return CurrentAssignmentDetail(
    key: AssignmentDetailKey(semesterId: 101, identityKey: 'backend:4001'),
    sync: const AssignmentDetailSyncEvidence(
      latestAttemptStatus: AssignmentDetailSyncStatus.success,
      latestAttemptFailureCategory: null,
      latestSuccessCompletedAtUtc: null,
    ),
    courseName: 'Algorithms',
    title: 'Lab 4',
    description: null,
    activityType: 'ASM',
    deadline: const MissingAssignmentDetailTimestamp(),
    backendReportedDeadlineExceeded: false,
    sourceCreatedAt: const MissingAssignmentDetailTimestamp(),
    submissionStatus: AssignmentSubmissionStatus.unsubmitted,
    backendReportedSubmissionLate: false,
    groupType: 'individual',
    groupName: null,
    groupMemberCount: 1,
    courseId: 11,
    backendActivityId: backendActivityId,
    leb2UserId: 2001,
    attachmentIds: attachmentIds,
    attachmentCount: attachmentIds.length,
    firstSeenAtUtc: DateTime.utc(2026, 9, 1),
    lastSeenAtUtc: DateTime.utc(2026, 9, 2),
    isBaseline: false,
    courseNotificationsMuted: false,
    reminders: const AssignmentDetailReminderEvidence(
      totalCount: 0,
      pendingReconciliationCount: 0,
      earliestReadyScheduledAtUtc: null,
    ),
    notificationHistory: const AssignmentDetailNotificationEvidence(
      recordCount: 0,
      latestRecordedAtUtc: null,
    ),
  );
}

final class _RecordingSink implements AttachmentFileSink {
  final writes = <({String fileName, int byteCount})>[];
  bool shouldThrow = false;

  @override
  Future<String> write({
    required String fileName,
    required List<int> bytes,
    bool openAfterSave = true,
  }) async {
    if (shouldThrow) {
      throw StateError('disk full');
    }
    writes.add((fileName: fileName, byteCount: bytes.length));
    return '/saved/$fileName';
  }
}

final class _FakeClient implements BackendApiClient {
  final attachmentCalls =
      <
        ({
          int semesterId,
          int classId,
          int activityId,
          int attachmentId,
          int userId,
        })
      >[];
  final archiveCalls =
      <({int semesterId, int classId, int activityId, int userId})>[];
  BackendTransportException? failure;

  @override
  Future<BackendFileDownload> downloadActivityAttachment({
    required int semesterId,
    required int classId,
    required int activityId,
    required int attachmentId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    final pending = failure;
    if (pending != null) {
      throw pending;
    }
    attachmentCalls.add((
      semesterId: semesterId,
      classId: classId,
      activityId: activityId,
      attachmentId: attachmentId,
      userId: userId,
    ));
    return BackendFileDownload(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      fileName: 'lab4.pdf',
      contentType: 'application/pdf',
    );
  }

  @override
  Future<BackendFileDownload> downloadActivityAttachmentArchive({
    required int semesterId,
    required int classId,
    required int activityId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    final pending = failure;
    if (pending != null) {
      throw pending;
    }
    archiveCalls.add((
      semesterId: semesterId,
      classId: classId,
      activityId: activityId,
      userId: userId,
    ));
    return BackendFileDownload(
      bytes: Uint8List.fromList(const [4, 5]),
      fileName: 'activity-4001.zip',
      contentType: 'application/zip',
    );
  }

  @override
  Future<List<Course>> getCourses({
    required int semesterId,
    BackendRequestCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<List<Semester>> getSemesters({
    BackendRequestCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) => throw UnimplementedError();
}

final class _FakeLearningClient implements BackendLearningActivityClient {
  final attachmentCalls =
      <
        ({
          int semesterId,
          int classId,
          int materialId,
          int attachmentId,
          int userId,
        })
      >[];
  final archiveCalls =
      <({int semesterId, int classId, int materialId, int userId})>[];

  @override
  Future<List<LearningMaterial>> getLearningMaterials({
    required int semesterId,
    required int classId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<BackendFileDownload> downloadLearningMaterialAttachment({
    required int semesterId,
    required int classId,
    required int materialId,
    required int attachmentId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    attachmentCalls.add((
      semesterId: semesterId,
      classId: classId,
      materialId: materialId,
      attachmentId: attachmentId,
      userId: userId,
    ));
    return BackendFileDownload(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      fileName: 'reading.pdf',
      contentType: 'application/pdf',
    );
  }

  @override
  Future<BackendFileDownload> downloadLearningMaterialAttachmentArchive({
    required int semesterId,
    required int classId,
    required int materialId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    archiveCalls.add((
      semesterId: semesterId,
      classId: classId,
      materialId: materialId,
      userId: userId,
    ));
    return BackendFileDownload(
      bytes: Uint8List.fromList(const [4, 5]),
      fileName: 'material-5001.zip',
      contentType: 'application/zip',
    );
  }
}
