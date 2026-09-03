import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/database/app_database.dart';
import 'package:leb2_watch/src/features/courses/data/course_material_cache_store.dart';

void main() {
  late AppDatabase database;
  late DriftCourseMaterialCacheStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftCourseMaterialCacheStore(database);
  });

  tearDown(() => database.close());

  test('round-trips cache identity and saved path per semester', () async {
    await database
        .into(database.semesters)
        .insert(SemestersCompanion.insert(semesterId: const Value(101)));
    await database
        .into(database.courses)
        .insert(
          CoursesCompanion.insert(
            semesterId: 101,
            courseId: 3001,
            name: 'Distributed Systems',
          ),
        );
    final key = const CourseMaterialFileKey(
      semesterId: 101,
      courseId: 3001,
      materialId: 5001,
      attachmentId: 6001,
    );
    final cachedAt = DateTime.utc(2026, 9, 3, 13);

    await store.markCached(
      key: key,
      displayName: 'reading.pdf',
      fileSize: '585 KB',
      savedPath: 'Downloads/LEB2/reading.pdf',
      cachedAtUtc: cachedAt,
    );

    final entries = await store.readForSemester(101);
    expect(entries[key]?.displayName, 'reading.pdf');
    expect(entries[key]?.fileSize, '585 KB');
    expect(entries[key]?.savedPath, 'Downloads/LEB2/reading.pdf');
    expect(entries[key]?.cachedAtUtc, cachedAt);
    expect(await store.readForSemester(102), isEmpty);
  });
}
