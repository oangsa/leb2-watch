/// A learning material published for one course.
final class LearningMaterial {
  const LearningMaterial({
    required this.id,
    required this.classId,
    required this.title,
    required this.description,
    required this.fileCount,
    required this.fileMaterials,
  });

  final int id;
  final int classId;
  final String title;
  final String description;
  final int fileCount;
  final List<LearningMaterialFile> fileMaterials;

  @override
  String toString() => 'LearningMaterial(redacted: true)';
}

/// Download metadata for one learning-material file.
final class LearningMaterialFile {
  const LearningMaterialFile({
    required this.id,
    required this.displayName,
    required this.fileSize,
    required this.fileType,
  });

  final int id;
  final String displayName;
  final String fileSize;
  final String fileType;

  @override
  String toString() => 'LearningMaterialFile(redacted: true)';
}
