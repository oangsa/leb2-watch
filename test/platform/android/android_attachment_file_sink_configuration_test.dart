import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android attachment sink uses public MediaStore Downloads', () {
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
    expect(activity, contains('configureAttachmentFileSink'));
  });
}
