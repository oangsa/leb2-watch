import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/attachment_download.dart';

/// Saves attachments into a `LEB2` folder the user can browse.
///
/// Desktop gets the real Downloads directory; mobile has no shared one that is
/// writable without extra permissions, so it uses the app's documents directory
/// instead — reachable through the system file picker and removed with the app.
final class LocalAttachmentFileSink implements AttachmentFileSink {
  const LocalAttachmentFileSink({Future<Directory> Function()? resolveRoot})
    : _resolveRoot = resolveRoot ?? _defaultRoot;

  final Future<Directory> Function() _resolveRoot;

  @override
  Future<String> write({
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
