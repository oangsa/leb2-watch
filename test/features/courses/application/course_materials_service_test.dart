import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/domain/learning_material_models.dart';
import 'package:leb2_watch/src/features/courses/application/course_materials_service.dart';
import 'package:leb2_watch/src/features/courses/data/course_preferences_store.dart';

void main() {
  test('reads materials for the selected course and saved identity', () async {
    final client = _FakeClient();
    final service = RemoteCourseMaterialsService(
      client: () => client,
      readUserId: () async => 2001,
    );

    final catalog = await service.read(
      const CourseKey(semesterId: 101, courseId: 3001),
    );

    expect(catalog.semesterId, 101);
    expect(catalog.classId, 3001);
    expect(catalog.userId, 2001);
    expect(catalog.materials.single.title, 'Reading');
    expect(client.listCall, (semesterId: 101, classId: 3001, userId: 2001));
  });

  test('does not call the backend without a saved identity', () async {
    final client = _FakeClient();
    final service = RemoteCourseMaterialsService(
      client: () => client,
      readUserId: () async => null,
    );

    await expectLater(
      service.read(const CourseKey(semesterId: 101, courseId: 3001)),
      throwsA(isA<CourseMaterialsUnavailableException>()),
    );
    expect(client.listCall, isNull);
  });

  test('forwards cancellation to the learning-material request', () async {
    final client = _FakeClient();
    final service = RemoteCourseMaterialsService(
      client: () => client,
      readUserId: () async => 2001,
    );
    final cancellation = BackendRequestCancellation();

    await service.read(
      const CourseKey(semesterId: 101, courseId: 3001),
      cancellation: cancellation,
    );

    expect(client.cancellation, same(cancellation));
  });

  test('redacts backend failures behind a stable unavailable error', () async {
    final service = RemoteCourseMaterialsService(
      client: () => (_FakeClient()..failure = StateError('private response')),
      readUserId: () async => 2001,
    );

    final error = await _capture(
      service.read(const CourseKey(semesterId: 101, courseId: 3001)),
    );

    expect(error, isA<CourseMaterialsUnavailableException>());
    expect(error.toString(), isNot(contains('private response')));
  });
}

Future<Object> _capture(Future<Object> operation) async {
  try {
    await operation;
  } on Object catch (error) {
    return error;
  }
  fail('Expected CourseMaterialsUnavailableException.');
}

final class _FakeClient implements BackendLearningActivityClient {
  ({int semesterId, int classId, int userId})? listCall;
  BackendRequestCancellation? cancellation;
  Object? failure;

  @override
  Future<List<LearningMaterial>> getLearningMaterials({
    required int semesterId,
    required int classId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    this.cancellation = cancellation;
    final pending = failure;
    if (pending != null) {
      throw pending;
    }
    listCall = (semesterId: semesterId, classId: classId, userId: userId);
    return const [
      LearningMaterial(
        id: 5001,
        classId: 3001,
        title: 'Reading',
        description: '',
        fileCount: 1,
        fileMaterials: [
          LearningMaterialFile(
            id: 6001,
            displayName: 'reading.pdf',
            fileSize: '585 KB',
            fileType: 'application/pdf',
          ),
        ],
      ),
    ];
  }

  @override
  Future<BackendFileDownload> downloadLearningMaterialAttachment({
    required int semesterId,
    required int classId,
    required int materialId,
    required int attachmentId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async => BackendFileDownload(
    bytes: Uint8List.fromList(const [1]),
    fileName: 'reading.pdf',
    contentType: 'application/pdf',
  );

  @override
  Future<BackendFileDownload> downloadLearningMaterialAttachmentArchive({
    required int semesterId,
    required int classId,
    required int materialId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async => BackendFileDownload(
    bytes: Uint8List.fromList(const [1]),
    fileName: 'material.zip',
    contentType: 'application/zip',
  );
}
