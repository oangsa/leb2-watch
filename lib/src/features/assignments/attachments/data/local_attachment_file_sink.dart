import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/attachment_download.dart';

const attachmentFileSinkChannel = MethodChannel(
  'dev.oangsa.leb2watch/attachment-file-sink',
);

/// Saves an attachment in Android's public Downloads collection.
final class AndroidAttachmentFileSink implements AttachmentFileSink {
  const AndroidAttachmentFileSink([this._channel = attachmentFileSinkChannel]);

  final MethodChannel _channel;

  @override
  Future<String> write({
    required String fileName,
    required List<int> bytes,
    bool openAfterSave = true,
  }) async {
    try {
      final path = await _channel
          .invokeMethod<String>('saveAttachment', <String, Object?>{
            'fileName': fileName,
            'bytes': Uint8List.fromList(bytes),
            'openAfterSave': openAfterSave,
          });
      if (path == null || path.trim().isEmpty) {
        throw const FileSystemException('Attachment path was unavailable.');
      }
      return path;
    } on PlatformException catch (error) {
      if (error.code == 'UNSUPPORTED_ANDROID_PUBLIC_STORAGE') {
        throw const _AndroidPublicStorageUnavailableException();
      }
      rethrow;
    }
  }

  @override
  String toString() => 'AndroidAttachmentFileSink(redacted: true)';
}

/// Saves attachments into a `LEB2` folder the user can browse.
///
/// Android 10 and newer use the public Downloads collection. Older Android
/// versions retain the private fallback because public storage needs a runtime
/// permission that this app does not request.
final class LocalAttachmentFileSink implements AttachmentFileSink {
  const LocalAttachmentFileSink({
    Future<Directory> Function()? resolveRoot,
    AttachmentFileSink? androidSink,
  }) : _resolveRoot = resolveRoot ?? _defaultRoot,
       _androidSink = androidSink ?? const AndroidAttachmentFileSink();

  final Future<Directory> Function() _resolveRoot;
  final AttachmentFileSink _androidSink;

  @override
  Future<String> write({
    required String fileName,
    required List<int> bytes,
    bool openAfterSave = true,
  }) async {
    if (Platform.isAndroid) {
      try {
        return await _androidSink.write(
          fileName: fileName,
          bytes: bytes,
          openAfterSave: openAfterSave,
        );
      } on _AndroidPublicStorageUnavailableException {
        // Android 9 and older use the private fallback below.
      }
    }

    return _writePrivate(fileName: fileName, bytes: bytes);
  }

  Future<String> _writePrivate({
    required String fileName,
    required List<int> bytes,
  }) async {
    final root = await _resolveRoot();
    final directory = Directory(p.join(root.path, 'LEB2'));
    await directory.create(recursive: true);

    final file = File(_availablePath(directory, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Keeps an already-downloaded file rather than overwriting it: two different
  /// activities can legitimately ship files with the same name.
  static String _availablePath(Directory directory, String fileName) {
    final safeName = fileName.isEmpty ? 'attachment' : fileName;
    var candidate = p.join(directory.path, safeName);
    if (!File(candidate).existsSync()) {
      return candidate;
    }

    final extension = p.extension(safeName);
    final stem = p.basenameWithoutExtension(safeName);
    for (var suffix = 2; suffix < 1000; suffix++) {
      candidate = p.join(directory.path, '$stem ($suffix)$extension');
      if (!File(candidate).existsSync()) {
        return candidate;
      }
    }
    // ponytail: give up on pretty names after 999 collisions and stamp the
    // time instead; switch to a content hash if this ever actually shows up.
    return p.join(
      directory.path,
      '$stem (${DateTime.now().millisecondsSinceEpoch})$extension',
    );
  }

  static Future<Directory> _defaultRoot() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }
    return await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  }

  @override
  String toString() => 'LocalAttachmentFileSink(redacted: true)';
}

final class _AndroidPublicStorageUnavailableException implements Exception {
  const _AndroidPublicStorageUnavailableException();
}
