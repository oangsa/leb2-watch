import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/session/session_lifecycle.dart';

const _maximumSemesterId = 2147483647;

final class SemesterCatalog {
  SemesterCatalog({
    required Iterable<int> semesterIds,
    required this.activeSemesterId,
  }) : semesterIds = List<int>.unmodifiable(semesterIds);

  factory SemesterCatalog.empty() =>
      SemesterCatalog(semesterIds: const [], activeSemesterId: null);

  final List<int> semesterIds;
  final int? activeSemesterId;

  bool get isEmpty => semesterIds.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is SemesterCatalog &&
      _listsEqual(other.semesterIds, semesterIds) &&
      other.activeSemesterId == activeSemesterId;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(semesterIds), activeSemesterId);

  @override
  String toString() => 'SemesterCatalog(redacted: true)';
}

sealed class SemesterCatalogMergeResult {
  const SemesterCatalogMergeResult();
}

final class SemesterCatalogMerged extends SemesterCatalogMergeResult {
  const SemesterCatalogMerged(this.catalog);

  final SemesterCatalog catalog;

  @override
  String toString() => 'SemesterCatalogMerged(redacted: true)';
}

final class SemesterCatalogMergeDiscarded extends SemesterCatalogMergeResult {
  const SemesterCatalogMergeDiscarded();

  @override
  String toString() => 'SemesterCatalogMergeDiscarded(redacted: true)';
}

abstract interface class SemesterSelectionStore {
  Future<SemesterCatalog> read();

  Future<SemesterCatalogMergeResult> mergeIfSessionCurrent(
    Iterable<int> semesterIds, {
    required SessionLifecycleSnapshot expectedSession,
  });

  Future<SemesterCatalog> select(int semesterId);
}

enum SemesterSelectionStoreOperation { read, merge, select }

final class SemesterSelectionStoreException implements Exception {
  const SemesterSelectionStoreException(this.operation);

  final SemesterSelectionStoreOperation operation;

  @override
  String toString() =>
      'SemesterSelectionStoreException('
      'operation: ${operation.name}, redacted: true)';
}

final class DriftSemesterSelectionStore implements SemesterSelectionStore {
  DriftSemesterSelectionStore(this._database);

  final AppDatabase _database;

  @override
  Future<SemesterCatalog> read() {
    return _run(
      SemesterSelectionStoreOperation.read,
      () => _database.transaction(_readCatalog),
    );
  }

  @override
  Future<SemesterCatalogMergeResult> mergeIfSessionCurrent(
    Iterable<int> semesterIds, {
    required SessionLifecycleSnapshot expectedSession,
  }) {
    final ids = semesterIds.toSet();
    if (ids.isEmpty) {
      throw ArgumentError.value(
        semesterIds,
        'semesterIds',
        'Must contain at least one semester.',
      );
    }
    for (final id in ids) {
      _validateSemesterId(id);
    }

    return _run(
      SemesterSelectionStoreOperation.merge,
      () => _database.transaction(() async {
        final storedSession = decodeStoredSessionLifecycle(
          await _database.select(_database.appSettings).getSingleOrNull(),
        );
        if (storedSession != expectedSession) {
          return const SemesterCatalogMergeDiscarded();
        }

        for (final id in ids) {
          await _database
              .into(_database.semesters)
              .insert(
                SemestersCompanion.insert(semesterId: Value(id)),
                mode: InsertMode.insertOrIgnore,
              );
        }
        return SemesterCatalogMerged(await _readCatalog());
      }),
    );
  }

  @override
  Future<SemesterCatalog> select(int semesterId) {
    _validateSemesterId(semesterId);
    return _run(
      SemesterSelectionStoreOperation.select,
      () => _database.transaction(() async {
        final exists =
            await (_database.selectOnly(_database.semesters)
                  ..addColumns([_database.semesters.semesterId])
                  ..where(_database.semesters.semesterId.equals(semesterId)))
                .getSingleOrNull();
        if (exists == null) {
          throw StateError('The semester is not cached.');
        }

        await _database
            .into(_database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion(
                singletonId: const Value(1),
                activeSemesterId: Value(semesterId),
              ),
            );
        return _readCatalog();
      }),
    );
  }

  Future<SemesterCatalog> _readCatalog() async {
    final rows = await (_database.select(
      _database.semesters,
    )..orderBy([(row) => OrderingTerm.desc(row.semesterId)])).get();
    final settings = await _database
        .select(_database.appSettings)
        .getSingleOrNull();
    return SemesterCatalog(
      semesterIds: rows.map((row) => row.semesterId),
      activeSemesterId: settings?.activeSemesterId,
    );
  }

  Future<T> _run<T>(
    SemesterSelectionStoreOperation operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on ArgumentError {
      rethrow;
    } on Object {
      throw SemesterSelectionStoreException(operation);
    }
  }

  void _validateSemesterId(int semesterId) {
    if (semesterId <= 0 || semesterId > _maximumSemesterId) {
      throw ArgumentError.value(
        semesterId,
        'semesterId',
        'Must be a positive int32.',
      );
    }
  }

  @override
  String toString() => 'DriftSemesterSelectionStore(redacted: true)';
}

bool _listsEqual(List<int> first, List<int> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
