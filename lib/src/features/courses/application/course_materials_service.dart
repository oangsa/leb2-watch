import '../../../core/network/backend_api_client.dart';
import '../../../core/network/domain/learning_material_models.dart';
import '../data/course_preferences_store.dart';

abstract interface class CourseMaterialsService {
  Future<CourseMaterialsCatalog> read(
    CourseKey key, {
    BackendRequestCancellation? cancellation,
  });
}

final class CourseMaterialsCatalog {
  CourseMaterialsCatalog({
    required this.semesterId,
    required this.classId,
    required this.userId,
    required Iterable<LearningMaterial> materials,
  }) : materials = List<LearningMaterial>.unmodifiable(materials);

  final int semesterId;
  final int classId;
  final int userId;
  final List<LearningMaterial> materials;

  @override
  String toString() => 'CourseMaterialsCatalog(redacted: true)';
}

final class CourseMaterialsUnavailableException implements Exception {
  const CourseMaterialsUnavailableException();

  @override
  String toString() => 'CourseMaterialsUnavailableException(redacted: true)';
}

final class RemoteCourseMaterialsService implements CourseMaterialsService {
  const RemoteCourseMaterialsService({
    required this.client,
    required this.readUserId,
  });

  final BackendLearningActivityClient Function() client;
  final Future<int?> Function() readUserId;

  @override
  Future<CourseMaterialsCatalog> read(
    CourseKey key, {
    BackendRequestCancellation? cancellation,
  }) async {
    try {
      final userId = await readUserId();
      if (userId == null || userId <= 0 || userId > 2147483647) {
        throw const CourseMaterialsUnavailableException();
      }
      final materials = await client().getLearningMaterials(
        semesterId: key.semesterId,
        classId: key.courseId,
        userId: userId,
        cancellation: cancellation,
      );
      return CourseMaterialsCatalog(
        semesterId: key.semesterId,
        classId: key.courseId,
        userId: userId,
        materials: materials,
      );
    } on CourseMaterialsUnavailableException {
      rethrow;
    } on Object {
      throw const CourseMaterialsUnavailableException();
    }
  }

  @override
  String toString() => 'RemoteCourseMaterialsService(redacted: true)';
}
