/// Writes a downloaded attachment somewhere the user can reach it.
///
/// A port rather than direct file access, so the download flow stays testable
/// and the platform's storage rules live in one adapter.
abstract interface class AttachmentFileSink {
  /// Writes [bytes] under [fileName] and returns the saved path. An existing
  /// file with the same name is never overwritten silently; the adapter
  /// disambiguates instead.
  Future<String> write({
    required String fileName,
    required List<int> bytes,
    bool openAfterSave = true,
  });
}

sealed class AttachmentDownloadResult {
  const AttachmentDownloadResult();

  @override
  String toString() => '$runtimeType(redacted: true)';
}

final class AttachmentDownloadSaved extends AttachmentDownloadResult {
  const AttachmentDownloadSaved({required this.fileName, required this.path});

  final String fileName;
  final String path;
}

enum AttachmentDownloadFailureReason {
  /// The activity has no LEB2 activity id, so it cannot be addressed.
  unsupportedActivity,

  /// The saved session is gone or rejected; the user has to sign in again.
  sessionExpired,

  /// LEB2 or the backend could not serve the file right now.
  unavailable,

  /// The file arrived but could not be written to storage.
  storageFailed,

  unknown,
}

final class AttachmentDownloadFailed extends AttachmentDownloadResult {
  const AttachmentDownloadFailed(this.reason);

  final AttachmentDownloadFailureReason reason;

  String get message => switch (reason) {
    AttachmentDownloadFailureReason.unsupportedActivity =>
      'This assignment has no downloadable files.',
    AttachmentDownloadFailureReason.sessionExpired =>
      'The session expired. Sign in again to download files.',
    AttachmentDownloadFailureReason.unavailable =>
      'LEB2 could not provide the file right now.',
    AttachmentDownloadFailureReason.storageFailed =>
      'The file could not be saved to this device.',
    AttachmentDownloadFailureReason.unknown => 'The download did not finish.',
  };
}
