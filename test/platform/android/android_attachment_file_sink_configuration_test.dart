import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android attachment sink saves and opens public Downloads files', () {
    final sink = File(
      'android/app/src/main/kotlin/dev/oangsa/leb2watch/AttachmentFileSink.kt',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/dev/oangsa/leb2watch/MainActivity.kt',
    ).readAsStringSync();

    expect(sink, contains('MediaStore.Downloads.EXTERNAL_CONTENT_URI'));
    expect(sink, contains('MediaStore.Downloads.RELATIVE_PATH'));
    expect(sink, contains('MediaStore.Downloads.IS_PENDING'));
    expect(sink, contains('Downloads/LEB2'));
    expect(sink, contains('Intent.ACTION_VIEW'));
    expect(sink, contains('Intent.FLAG_GRANT_READ_URI_PERMISSION'));
    expect(sink, contains('context.startActivity(intent)'));
    expect(sink, contains('The file remains saved'));
    expect(activity, contains('configureAttachmentFileSink'));
  });
}
