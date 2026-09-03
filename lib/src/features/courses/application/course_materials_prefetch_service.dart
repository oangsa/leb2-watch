import '../../../core/network/backend_api_client.dart';
import '../../assignments/attachments/application/attachment_download_service.dart';
import '../../assignments/attachments/domain/attachment_download.dart';
import '../data/course_material_cache_store.dart';
import '../data/course_preferences_store.dart';
import 'course_materials_service.dart';

/// Coordinates the course-file cache without adding another user setting.
abstract interface class CourseMaterialsPrefetcher {
  Future<CourseMaterialPrefetchResult> prefetch({
    required Iterable<CourseKey> courses,
    int? expectedUserId,
    BackendRequestCancellation? cancellation,
  });

  Future<CourseMaterialPrefetchResult> prefetchActiveSemester({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  });
}

final class CourseMaterialPrefetchResult {
  const CourseMaterialPrefetchResult({
    this.courses = 0,
    this.failedCourses = 0,
    this.files = 0,
    this.downloaded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.cancelled = false,
  });

  final int courses;
  final int failedCourses;
  final int files;
  final int downloaded;
  final int skipped;
  final int failed;
  final bool cancelled;

  @override
  String toString() => 'CourseMaterialPrefetchResult(redacted: true)';
}

final class CourseMaterialsPrefetchService
    implements CourseMaterialsPrefetcher {
  const CourseMaterialsPrefetchService({
    required this.preferencesStore,
    required this.materialsService,
    required this.downloadService,
    required this.cacheStore,
    this.nowUtc,
  });

  final CoursePreferencesStore preferencesStore;
  final CourseMaterialsService materialsService;
  final AttachmentDownloadService downloadService;
  final CourseMaterialCacheStore cacheStore;
  final DateTime Function()? nowUtc;

  @override
  Future<CourseMaterialPrefetchResult> prefetchActiveSemester({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) async {
    final catalog = await preferencesStore.readActiveCatalog();
    if (catalog.activeSemesterId != semesterId || catalog.courses.isEmpty) {
      return const CourseMaterialPrefetchResult();
    }
    return prefetch(
      courses: catalog.courses.map((course) => course.key),
      expectedUserId: userId,
      cancellation: cancellation,
    );
  }

  @override
  Future<CourseMaterialPrefetchResult> prefetch({
    required Iterable<CourseKey> courses,
    int? expectedUserId,
    BackendRequestCancellation? cancellation,
  }) async {
    final courseList = courses.toList(growable: false);
    if (courseList.isEmpty || cancellation?.isCancelled == true) {
      return CourseMaterialPrefetchResult(
        courses: courseList.length,
        cancelled: cancellation?.isCancelled == true,
      );
    }

    final cached = Map.of(
      await cacheStore.readForSemester(courseList.first.semesterId),
    );
    var failedCourses = 0;
    var files = 0;
    var downloaded = 0;
    var skipped = 0;
    var failed = 0;

    for (final course in courseList) {
      if (cancellation?.isCancelled == true) {
        return CourseMaterialPrefetchResult(
          courses: courseList.length,
          failedCourses: failedCourses,
          files: files,
          downloaded: downloaded,
          skipped: skipped,
          failed: failed,
          cancelled: true,
        );
      }

      final catalog = await _readCourse(course, cancellation: cancellation);
      if (catalog == null ||
          (expectedUserId != null && catalog.userId != expectedUserId)) {
        failedCourses += 1;
        continue;
      }

      for (final material in catalog.materials) {
        for (final file in material.fileMaterials) {
          files += 1;
          if (cancellation?.isCancelled == true) {
            return CourseMaterialPrefetchResult(
              courses: courseList.length,
              failedCourses: failedCourses,
              files: files,
              downloaded: downloaded,
              skipped: skipped,
              failed: failed,
              cancelled: true,
            );
          }

          final key = CourseMaterialFileKey(
            semesterId: course.semesterId,
            courseId: course.courseId,
            materialId: material.id,
            attachmentId: file.id,
          );
          final existing = cached[key];
          if (existing != null &&
              existing.displayName == file.displayName &&
              existing.fileSize == file.fileSize) {
            skipped += 1;
            continue;
          }

          final result = await downloadService.downloadLearningMaterialOne(
            semesterId: catalog.semesterId,
            classId: catalog.classId,
            materialId: material.id,
            attachmentId: file.id,
            userId: catalog.userId,
            openAfterSave: false,
            cancellation: cancellation,
          );
          if (result case AttachmentDownloadSaved(:final path)) {
            final cachedAtUtc = (nowUtc ?? DateTime.now)().toUtc();
            try {
              await cacheStore.markCached(
                key: key,
                displayName: file.displayName,
                fileSize: file.fileSize,
                savedPath: path,
                cachedAtUtc: cachedAtUtc,
              );
              cached[key] = CachedCourseMaterialFile(
                key: key,
                displayName: file.displayName,
                fileSize: file.fileSize,
                savedPath: path,
                cachedAtUtc: cachedAtUtc,
              );
              downloaded += 1;
            } on Object {
              failed += 1;
            }
          } else {
            failed += 1;
          }
        }
      }
    }

    return CourseMaterialPrefetchResult(
      courses: courseList.length,
      failedCourses: failedCourses,
      files: files,
      downloaded: downloaded,
      skipped: skipped,
      failed: failed,
    );
  }

  Future<CourseMaterialsCatalog?> _readCourse(
    CourseKey key, {
    BackendRequestCancellation? cancellation,
  }) async {
    try {
      return await materialsService.read(key, cancellation: cancellation);
    } on Object {
      return null;
    }
  }

  @override
  String toString() => 'CourseMaterialsPrefetchService(redacted: true)';
}
