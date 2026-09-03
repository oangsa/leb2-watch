import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/features/assignments/attachments/data/local_attachment_file_sink.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(
    () => messenger.setMockMethodCallHandler(attachmentFileSinkChannel, null),
  );

  test('sends bytes to the Android public download channel', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(attachmentFileSinkChannel, (call) async {
      received = call;
      return 'Downloads/LEB2/reading.pdf';
    });

    final path = await const AndroidAttachmentFileSink().write(
      fileName: 'reading.pdf',
      bytes: const [1, 2, 3],
      contentType: 'application/pdf',
    );

    expect(path, 'Downloads/LEB2/reading.pdf');
    expect(received?.method, 'saveAttachment');
    final arguments = received?.arguments as Map<Object?, Object?>;
    expect(arguments['fileName'], 'reading.pdf');
    expect(arguments['bytes'], orderedEquals(const [1, 2, 3]));
    expect(arguments['contentType'], 'application/pdf');
    expect(arguments['openAfterSave'], isTrue);
  });

  test('preserves native save failures for the download service', () async {
    messenger.setMockMethodCallHandler(
      attachmentFileSinkChannel,
      (_) async => throw PlatformException(code: 'SAVE_FAILED'),
    );

    await expectLater(
      const AndroidAttachmentFileSink().write(
        fileName: 'reading.pdf',
        bytes: const [1],
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  test('can save without opening a viewer for background caching', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(attachmentFileSinkChannel, (call) async {
      received = call;
      return 'Downloads/LEB2/reading.pdf';
    });

    await const AndroidAttachmentFileSink().write(
      fileName: 'reading.pdf',
      bytes: const [1],
      openAfterSave: false,
    );

    final arguments = received?.arguments as Map<Object?, Object?>;
    expect(arguments['openAfterSave'], isFalse);
  });
}
