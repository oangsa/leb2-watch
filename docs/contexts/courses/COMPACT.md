# Courses

## Status

Implemented for the nightly build.

## Purpose

Show saved courses and course learning materials with the same compact, card-based hierarchy as Assignments.

## Scope

- Shared semester page header and course selection.
- Per-course notification and background-monitoring preferences in a gear-triggered modal.
- Background caching of every learning-material file in the active semester.
- Reuse of the assignment background-check cadence and scheduler.

## Non-scope

- No separate course-fetch cadence or new user setting.
- Manual download behavior remains available and opens a saved file when the platform supports it.

## User-visible behavior

The Courses page uses the shared card header, displays the active semester and the assignment check cadence, and keeps settings behind the header gear button. The main page focuses on course selection and files; global and per-course settings live in the modal.

Course files are downloaded silently into the existing attachment destination. A local manifest keyed by semester, course, learning material, and attachment prevents repeated downloads while allowing changed file metadata to be fetched again.

## Architecture

`CourseMaterialsPrefetchService` reads the active course catalog, fetches each course's learning-material metadata, downloads uncached files through `AttachmentDownloadService`, and records successful saves in `CourseMaterialCacheStore`. `BackgroundSyncRunner` invokes it after a successful assignment synchronization, including a fresh-file prefetch when the assignment request itself is skipped as recently completed.

`AttachmentFileSink.write` accepts `openAfterSave`; user downloads keep the default, while prefetch passes `false`. Android honors the flag before launching a viewer.

## Important files

- `lib/src/features/courses/presentation/course_preferences_page.dart`
- `lib/src/features/courses/application/course_materials_prefetch_service.dart`
- `lib/src/features/courses/data/course_material_cache_store.dart`
- `lib/src/core/database/database_tables.dart`
- `lib/src/core/database/app_database.dart`
- `lib/src/app/design_system/widgets/app_page_header.dart`

## Data model

Schema 24 adds `course_material_cache`, storing file identity, display metadata, saved path, and cache time. The table is scoped to a semester and cascades when that semester is removed.

## Decisions

- The existing `BackgroundFetchCadence` is the sole cadence source.
- Prefetch is best effort and never changes a successful assignment-sync result.
- Native file opening is opt-out for automated work so caching cannot interrupt the user.

## Failure behavior

Metadata or file failures leave the affected file unmarked; the next assignment check retries it. Manual course-file downloads remain usable if prefetch composition or network access is unavailable.

## Tests

- `test/features/courses/application/course_materials_prefetch_service_test.dart`
- `test/features/courses/data/course_material_cache_store_test.dart`
- `test/features/courses/presentation/course_preferences_page_test.dart`
- `test/features/background_sync/application/background_sync_runner_test.dart`

## Validation evidence

Focused course tests passed (37 tests), the expanded affected regression suite passed (185 tests), and all 18 memory-safe Flutter shards passed across 173 test files. Dart formatting and Drift code generation also passed. `dart analyze` remains blocked by the `riverpod_lint` plugin attempting network access and writing its cache outside the writable workspace.

## Known limitations

The manifest records a successful saved path but does not probe whether a user later deletes that public file outside the app; a changed server filename or file size causes a fresh download.
