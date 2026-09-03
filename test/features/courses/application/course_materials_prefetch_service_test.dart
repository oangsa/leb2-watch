import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/domain/backend_models.dart';
import 'package:leb2_watch/src/core/network/domain/learning_material_models.dart';
import 'package:leb2_watch/src/features/assignments/attachments/application/attachment_download_service.dart';
import 'package:leb2_watch/src/features/assignments/attachments/domain/attachment_download.dart';
import 'package:leb2_watch/src/features/courses/application/course_materials_prefetch_service.dart';
import 'package:leb2_watch/src/features/courses/application/course_materials_service.dart';
import 'package:leb2_watch/src/features/courses/data/course_material_cache_store.dart';
import 'package:leb2_watch/src/features/courses/data/course_preferences_store.dart';

void main() {
  test('downloads every new file silently and skips cached files', () async {
    final course = const CourseKey(semesterId: 101, courseId: 3001);
    final cache = _FakeCacheStore();
    final sink = _RecordingSink();
    final client = _LearningClient();
    final downloader = AttachmentDownloadService(
      () => _UnusedApiClient(),
      sink,
      learningActivityClient: () => client,
    );
    final service = CourseMaterialsPrefetchService(
      preferencesStore: _FakePreferencesStore(),
      materialsService: _FakeMaterialsService(
        CourseMaterialsCatalog(
          semesterId: 101,
          classId: 3001,
          userId: 2001,
          materials: [
            const LearningMaterial(
              id: 5001,
              classId: 3001,
              title: 'Reading',
              description: '',
              fileCount: 2,
              fileMaterials: [
                LearningMaterialFile(
                  id: 6001,
                  displayName: 'reading.pdf',
                  fileSize: '10 KB',
                  fileType: 'application/pdf',
                ),
                LearningMaterialFile(
                  id: 6002,
                  displayName: 'notes.txt',
                  fileSize: '2 KB',
                  fileType: 'text/plain',
                ),
              ],
            ),
          ],
        ),
      ),
      downloadService: downloader,
      cacheStore: cache,
      nowUtc: () => DateTime.utc(2026, 9, 3),
    );

    final first = await service.prefetch(courses: [course]);
    final second = await service.prefetch(courses: [course]);

    expect(first.downloaded, 2);
    expect(first.skipped, 0);
    expect(second.downloaded, 0);
    expect(second.skipped, 2);
    expect(client.attachmentIds, [6001, 6002]);
    expect(sink.openAfterSaveValues, [false, false]);
    expect(cache.entries, hasLength(2));
  });
}

final class _FakeMaterialsService implements CourseMaterialsService {
  const _FakeMaterialsService(this.catalog);

  final CourseMaterialsCatalog catalog;

  @override
  Future<CourseMaterialsCatalog> read(
    CourseKey key, {
    BackendRequestCancellation? cancellation,
  }) async => catalog;
}

final class _FakePreferencesStore implements CoursePreferencesStore {
  @override
  Stream<ActiveCourseCatalog> watchActiveCatalog() => const Stream.empty();

  @override
  Future<ActiveCourseCatalog> readActiveCatalog() async =>
      ActiveCourseCatalog(activeSemesterId: 101, courses: const []);

  @override
  Future<CoursePreferenceWriteResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  }) => throw UnimplementedError();

  @override
  Future<CoursePreferenceWriteResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  }) => throw UnimplementedError();

  @override
  Future<CoursePreference?> readCurrentCoursePreference(CourseKey key) =>
      throw UnimplementedError();

  @override
  Future<Set<CourseKey>> readBackgroundMonitoredCourses(int semesterId) =>
      throw UnimplementedError();
}

final class _FakeCacheStore implements CourseMaterialCacheStore {
  final entries = <CourseMaterialFileKey, CachedCourseMaterialFile>{};

  @override
  Future<Map<CourseMaterialFileKey, CachedCourseMaterialFile>> readForSemester(
    int semesterId,
  ) async => Map.unmodifiable({
    for (final entry in entries.entries)
      if (entry.key.semesterId == semesterId) entry.key: entry.value,
  });

  @override
  Future<void> markCached({
    required CourseMaterialFileKey key,
    required String displayName,
    required String fileSize,
    required String savedPath,
    required DateTime cachedAtUtc,
  }) async {
    entries[key] = CachedCourseMaterialFile(
      key: key,
      displayName: displayName,
      fileSize: fileSize,
      savedPath: savedPath,
      cachedAtUtc: cachedAtUtc,
    );
  }
}

final class _RecordingSink implements AttachmentFileSink {
  final openAfterSaveValues = <bool>[];

  @override
  Future<String> write({
    required String fileName,
    required List<int> bytes,
    bool openAfterSave = true,
  }) async {
    openAfterSaveValues.add(openAfterSave);
    return '/saved/$fileName';
  }
}

final class _LearningClient implements BackendLearningActivityClient {
  final attachmentIds = <int>[];

  @override
  Future<List<LearningMaterial>> getLearningMaterials({
    required int semesterId,
    required int classId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async => const [];

  @override
  Future<BackendFileDownload> downloadLearningMaterialAttachment({
    required int semesterId,
    required int classId,
    required int materialId,
    required int attachmentId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    attachmentIds.add(attachmentId);
    return BackendFileDownload(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      fileName: 'file-$attachmentId.bin',
      contentType: 'application/octet-stream',
    );
  }

  @override
  Future<BackendFileDownload> downloadLearningMaterialAttachmentArchive({
    required int semesterId,
    required int classId,
    required int materialId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) => throw UnimplementedError();
}

final class _UnusedApiClient implements BackendApiClient {
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

  @override
  Future<BackendFileDownload> downloadActivityAttachment({
    required int semesterId,
    required int classId,
    required int activityId,
    required int attachmentId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<BackendFileDownload> downloadActivityAttachmentArchive({
    required int semesterId,
    required int classId,
    required int activityId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) => throw UnimplementedError();
}
