import '../../../../core/network/backend_api_client.dart';
import '../../../../core/network/backend_transport_failure.dart';
import '../../detail/application/assignment_detail_service.dart';
import '../domain/attachment_download.dart';

/// Downloads assignment attachments through the backend and saves them.
///
/// The backend streams from LEB2 and names each file, so this only decides
/// where the bytes land and how a failure reads.
final class AttachmentDownloadService {
  const AttachmentDownloadService(this._client, this._sink);

  /// Resolved per download, not at composition time, so building this service
  /// costs nothing and needs no backend configuration until a file is actually
  /// requested.
  final BackendApiClient Function() _client;
  final AttachmentFileSink _sink;

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

    final BackendFileDownload download;
    try {
      download = await request(activityId);
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
      );
      return AttachmentDownloadSaved(
        fileName: download.fileName,
        path: path,
      );
    } on Object {
      return const AttachmentDownloadFailed(
        AttachmentDownloadFailureReason.storageFailed,
      );
    }
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
