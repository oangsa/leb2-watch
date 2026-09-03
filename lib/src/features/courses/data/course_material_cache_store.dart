import '../../../core/database/app_database.dart';

const _maximumIdentifier = 2147483647;

final class CourseMaterialFileKey {
  const CourseMaterialFileKey({
    required this.semesterId,
    required this.courseId,
    required this.materialId,
    required this.attachmentId,
  });

  final int semesterId;
  final int courseId;
  final int materialId;
  final int attachmentId;

  @override
  bool operator ==(Object other) =>
      other is CourseMaterialFileKey &&
      other.semesterId == semesterId &&
      other.courseId == courseId &&
      other.materialId == materialId &&
      other.attachmentId == attachmentId;

  @override
  int get hashCode =>
      Object.hash(semesterId, courseId, materialId, attachmentId);

  @override
  String toString() => 'CourseMaterialFileKey(redacted: true)';
}

final class CachedCourseMaterialFile {
  const CachedCourseMaterialFile({
    required this.key,
    required this.displayName,
    required this.fileSize,
    required this.savedPath,
    required this.cachedAtUtc,
  });

  final CourseMaterialFileKey key;
  final String displayName;
  final String fileSize;
  final String savedPath;
  final DateTime cachedAtUtc;

  @override
  String toString() => 'CachedCourseMaterialFile(redacted: true)';
}

abstract interface class CourseMaterialCacheStore {
  Future<Map<CourseMaterialFileKey, CachedCourseMaterialFile>> readForSemester(
    int semesterId,
  );

  Future<void> markCached({
    required CourseMaterialFileKey key,
    required String displayName,
    required String fileSize,
    required String savedPath,
    required DateTime cachedAtUtc,
  });
}

final class CourseMaterialCacheStoreException implements Exception {
  const CourseMaterialCacheStoreException();

  @override
  String toString() => 'CourseMaterialCacheStoreException(redacted: true)';
}

final class DriftCourseMaterialCacheStore implements CourseMaterialCacheStore {
  const DriftCourseMaterialCacheStore(this._database);

  final AppDatabase _database;

  @override
  Future<Map<CourseMaterialFileKey, CachedCourseMaterialFile>> readForSemester(
    int semesterId,
  ) async {
    _validateIdentifier(semesterId, 'semesterId');
    try {
      final rows = await (_database.select(
        _database.courseMaterialCacheEntries,
      )..where((row) => row.semesterId.equals(semesterId))).get();
      return Map.unmodifiable({
        for (final row in rows)
          CourseMaterialFileKey(
            semesterId: row.semesterId,
            courseId: row.courseId,
            materialId: row.materialId,
            attachmentId: row.attachmentId,
          ): CachedCourseMaterialFile(
            key: CourseMaterialFileKey(
              semesterId: row.semesterId,
              courseId: row.courseId,
              materialId: row.materialId,
              attachmentId: row.attachmentId,
            ),
            displayName: row.displayName,
            fileSize: row.fileSize,
            savedPath: row.savedPath,
            cachedAtUtc: row.cachedAtUtc,
          ),
      });
    } on Object {
      throw const CourseMaterialCacheStoreException();
    }
  }

  @override
  Future<void> markCached({
    required CourseMaterialFileKey key,
    required String displayName,
    required String fileSize,
    required String savedPath,
    required DateTime cachedAtUtc,
  }) async {
    _validateKey(key);
    if (displayName.trim().isEmpty ||
        fileSize.trim().isEmpty ||
        savedPath.trim().isEmpty) {
      throw ArgumentError('cache metadata must not be blank');
    }
    try {
      await _database
          .into(_database.courseMaterialCacheEntries)
          .insertOnConflictUpdate(
            CourseMaterialCacheEntriesCompanion.insert(
              semesterId: key.semesterId,
              courseId: key.courseId,
              materialId: key.materialId,
              attachmentId: key.attachmentId,
              displayName: displayName,
              fileSize: fileSize,
              savedPath: savedPath,
              cachedAtUtc: cachedAtUtc,
            ),
          );
    } on Object {
      throw const CourseMaterialCacheStoreException();
    }
  }

  static void _validateKey(CourseMaterialFileKey key) {
    _validateIdentifier(key.semesterId, 'semesterId');
    _validateIdentifier(key.courseId, 'courseId');
    _validateIdentifier(key.materialId, 'materialId');
    _validateIdentifier(key.attachmentId, 'attachmentId');
  }

  static void _validateIdentifier(int value, String name) {
    if (value <= 0 || value > _maximumIdentifier) {
      throw ArgumentError.value(value, name);
    }
  }

  @override
  String toString() => 'DriftCourseMaterialCacheStore(redacted: true)';
}
