import '../../../../core/network/backend_api_client.dart';
import '../../../../core/network/backend_transport_failure.dart';
import '../../detail/application/assignment_detail_service.dart';
import '../domain/attachment_download.dart';

/// Downloads assignment attachments through the backend and saves them.
///
/// The backend streams from LEB2 and names each file, so this only decides
/// where the bytes land and how a failure reads.
final class AttachmentDownloadService {
  const AttachmentDownloadService(
    this._client,
    this._sink, {
    this.learningActivityClient,
  });

  /// Resolved per download, not at composition time, so building this service
  /// costs nothing and needs no backend configuration until a file is actually
  /// requested.
  final BackendApiClient Function() _client;
  final AttachmentFileSink _sink;
  final BackendLearningActivityClient Function()? learningActivityClient;

  Future<AttachmentDownloadResult> downloadOne({
    required CurrentAssignmentDetail detail,
    required int attachmentId,
  }) {
    return _download(
      detail: detail,
      request: (activityId) => _client().downloadActivityAttachment(
        semesterId: detail.key.semesterId,
        classId: detail.courseId,
        activityId: activityId,
        attachmentId: attachmentId,
        userId: detail.leb2UserId,
      ),
    );
  }

  /// Downloads every attachment on the activity as one archive. The backend
  /// builds it, so this stays a single request no matter the file count.
  Future<AttachmentDownloadResult> downloadAll({
    required CurrentAssignmentDetail detail,
  }) {
    return _download(
      detail: detail,
      request: (activityId) => _client().downloadActivityAttachmentArchive(
        semesterId: detail.key.semesterId,
        classId: detail.courseId,
        activityId: activityId,
        userId: detail.leb2UserId,
      ),
    );
  }

  Future<AttachmentDownloadResult> downloadLearningMaterialOne({
    required int semesterId,
    required int classId,
    required int materialId,
    required int attachmentId,
    required int userId,
    bool openAfterSave = true,
    BackendRequestCancellation? cancellation,
  }) {
    final client = learningActivityClient;
    if (client == null ||
        !_validIds([semesterId, classId, materialId, attachmentId, userId])) {
      return Future.value(
        const AttachmentDownloadFailed(
          AttachmentDownloadFailureReason.unsupportedActivity,
        ),
      );
    }
    return _saveDownload(
      request: () => client().downloadLearningMaterialAttachment(
        semesterId: semesterId,
        classId: classId,
        materialId: materialId,
        attachmentId: attachmentId,
        userId: userId,
        cancellation: cancellation,
      ),
      openAfterSave: openAfterSave,
    );
  }

  Future<AttachmentDownloadResult> downloadLearningMaterialAll({
    required int semesterId,
    required int classId,
    required int materialId,
    required int userId,
    bool openAfterSave = true,
    BackendRequestCancellation? cancellation,
  }) {
    final client = learningActivityClient;
    if (client == null ||
        !_validIds([semesterId, classId, materialId, userId])) {
      return Future.value(
        const AttachmentDownloadFailed(
          AttachmentDownloadFailureReason.unsupportedActivity,
        ),
      );
    }
    return _saveDownload(
      request: () => client().downloadLearningMaterialAttachmentArchive(
        semesterId: semesterId,
        classId: classId,
        materialId: materialId,
        userId: userId,
        cancellation: cancellation,
      ),
      openAfterSave: openAfterSave,
    );
  }

  Future<AttachmentDownloadResult> _download({
    required CurrentAssignmentDetail detail,
    required Future<BackendFileDownload> Function(int activityId) request,
  }) async {
    final activityId = detail.backendActivityId;
    if (activityId == null || detail.attachmentIds.isEmpty) {
      return const AttachmentDownloadFailed(
        AttachmentDownloadFailureReason.unsupportedActivity,
      );
    }

    return _saveDownload(request: () => request(activityId));
  }

  Future<AttachmentDownloadResult> _saveDownload({
    required Future<BackendFileDownload> Function() request,
    bool openAfterSave = true,
  }) async {
    final BackendFileDownload download;
    try {
      download = await request();
    } on BackendTransportException catch (failure) {
      return AttachmentDownloadFailed(_mapFailure(failure));
    } on Object {
      return const AttachmentDownloadFailed(
        AttachmentDownloadFailureReason.unknown,
      );
    }

    try {
      final path = await _sink.write(
        fileName: download.fileName,
        bytes: download.bytes,
        openAfterSave: openAfterSave,
      );
      return AttachmentDownloadSaved(fileName: download.fileName, path: path);
    } on Object {
      return const AttachmentDownloadFailed(
        AttachmentDownloadFailureReason.storageFailed,
      );
    }
  }

  static bool _validIds(Iterable<int> ids) {
    return ids.every((id) => id > 0 && id <= 2147483647);
  }

  static AttachmentDownloadFailureReason _mapFailure(
    BackendTransportException failure,
  ) {
    if (failure.httpError?.responseCode == 'SESSION_EXPIRED' ||
        failure.httpError?.statusCode == 401) {
      return AttachmentDownloadFailureReason.sessionExpired;
    }
    return switch (failure.kind) {
      BackendTransportFailureKind.missingCredential ||
      BackendTransportFailureKind.missingAccessKey ||
      BackendTransportFailureKind.invalidAccessKey =>
        AttachmentDownloadFailureReason.sessionExpired,
      BackendTransportFailureKind.connectionTimeout ||
      BackendTransportFailureKind.sendTimeout ||
      BackendTransportFailureKind.receiveTimeout ||
      BackendTransportFailureKind.transformTimeout ||
      BackendTransportFailureKind.connectionError ||
      BackendTransportFailureKind.httpResponse ||
      BackendTransportFailureKind.invalidResponse =>
        AttachmentDownloadFailureReason.unavailable,
      _ => AttachmentDownloadFailureReason.unknown,
    };
  }

  @override
  String toString() => 'AttachmentDownloadService(redacted: true)';
}
