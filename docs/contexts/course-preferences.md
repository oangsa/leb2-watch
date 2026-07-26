# Course Preferences

## Status

Completed for offline course controls, saved per-course notification and
background-effect preferences, exact saved-snapshot counts, fail-closed
consumer policy, and the real `/courses` route. The shared Dart and Flutter
implementation is covered by focused tests. Linux is the only native target
available for build verification on this host.

## Purpose

Give users local, per-course control over future notification and background
effects while keeping the course list and saved counts available without a
network request.

## Scope

- Show courses belonging to the locally selected semester.
- Show a post-baseline activity count and a saved upcoming-deadline count.
- Persist notification mute and background-monitoring preferences per
  `(semester_id, course_id)`.
- Preserve preferences if a course disappears from a later snapshot and then
  reappears.
- Expose application-owned policy reads for later notification and background
  consumers.
- Render no-active-semester, no-saved-courses, loading, storage-error,
  write-pending, stale-write, and write-failure states.
- Replace the `/courses` placeholder with a responsive, virtualized local
  control ledger.

## Non-scope

- Fetching courses from a separate backend endpoint.
- Skipping courses in the semester-wide snapshot request.
- Generating notifications or running background work.
- Global notification settings, reminder offsets, or desktop autostart.
- Treating post-baseline activity count as an unread count.
- Parsing backend deadline strings, applying a live clock, or inferring
  assignment completion.
- Account partitioning of existing semester-scoped cache data.

## User-visible behavior

The course route opens saved data only; visiting it does not start a network
request. With an active semester and cached courses, users see a bounded-width
list ordered by course name and then course ID. Each row shows:

- `New activities`: current activities whose durable seen identity was
  discovered after the semester baseline. Viewing the page does not clear the
  count.
- `Upcoming deadlines`: current activities with a saved deadline source that
  the backend snapshot did not report as exceeded.
- `Mute notifications`: suppresses later local notifications for that course.
- `Background monitoring`: controls later background effects after the shared
  semester snapshot has downloaded; it does not skip that download.

Writes are pessimistic. Both controls for a row are disabled until Drift emits
the persisted value. A failed or stale write keeps the prior saved value and
shows bounded, redacted guidance.

## Architecture

`DriftCoursePreferencesStore` joins the singleton active-semester setting to
cached courses, activities, seen identities, and optional preferences. It
aggregates exact counts into immutable, redacted `CourseSummary` values and
exposes the catalog as a Drift watch stream.

`LocalCoursePreferencesService` maps storage results to presentation-safe
updates and implements `CourseEffectPolicyReader`. The policy seam is separate
from the widget service so future effect producers do not depend on UI state.
Storage exceptions are converted to safe failures.

Riverpod composes one store and service from the existing application database.
`CoursePreferencesRoute` owns bounded provider loading/error states, while
`CoursePreferencesPage` owns the local stream, persistence interactions, and
responsive presentation. Widgets import neither Drift nor network types.

## Important files

- `lib/src/features/courses/data/course_preferences_store.dart` — immutable
  catalog values, Drift adapter, preference writes, count aggregation, and
  policy reads.
- `lib/src/features/courses/application/course_preferences_service.dart` —
  presentation update results and fail-closed consumer policy.
- `lib/src/features/courses/presentation/course_preferences_route.dart` —
  Riverpod route adapter and initialization retry.
- `lib/src/features/courses/presentation/course_preferences_page.dart` —
  responsive local control ledger and persistence states.
- `lib/src/core/database/database_tables.dart` — schema-v7 preference table.
- `lib/src/core/database/app_database.dart` — ordered v1-v6-to-v7 migration.
- `lib/src/app/app_dependencies.dart` — feature providers.
- `lib/src/app/routing/app_router.dart` — real `/courses` route.
- `test/features/courses/` — store, service/policy, and widget tests.
- `test/core/database/v6_app_database.dart` — frozen pre-v7 migration fixture.
- `test/app/routing/app_router_test.dart` — course route and shell integration.

## Contracts and interfaces

The presentation-facing service is:

```dart
abstract interface class CoursePreferencesService {
  Stream<ActiveCourseCatalog> watchCatalog();
  Future<CoursePreferenceUpdateResult> setNotificationsMuted(
    CourseKey key, {
    required bool muted,
  });
  Future<CoursePreferenceUpdateResult> setBackgroundMonitoringEnabled(
    CourseKey key, {
    required bool enabled,
  });
}
```

The consumer seam exposes `readPolicy` and
`readBackgroundMonitoredCourses`. `CourseEffectPolicy.allowsNotification`
requires a known current course, available storage, and an unmuted preference.
A background-triggered notification also requires background monitoring.
`allowsBackgroundEffect` requires the same known/storage checks and enabled
monitoring.

Keys accept positive int32 semester and course IDs only. Public values and
exceptions redact course data from `toString`.

## Data model

Schema version 7 adds:

```text
course_preferences
├── semester_id                    INTEGER NOT NULL
├── course_id                      INTEGER NOT NULL
├── notifications_muted            INTEGER NOT NULL DEFAULT 0
└── background_monitoring_enabled  INTEGER NOT NULL DEFAULT 1
```

The composite primary key is `(semester_id, course_id)`. Both IDs must be
positive. `semester_id` references `semesters` with `ON DELETE CASCADE`.
There is intentionally no foreign key to the current `courses` snapshot, so a
user preference survives course removal and applies again if that stable
course ID reappears in the same semester.

Missing rows use notification-unmuted and background-monitoring-enabled
defaults. No credential or remote user-specific state is added.

## State and control flow

1. The route opens the application-owned service from the local database.
2. The page subscribes to one active-catalog watch.
3. The store reads the active semester and locally saved snapshot tables.
4. Rows are aggregated and sorted before the immutable catalog is emitted.
5. A control interaction starts one row-scoped pessimistic write.
6. The store transaction verifies the same semester remains active and the
   course still exists, then upserts the preference.
7. A matching watched value clears the pending state. A stale key or storage
   failure clears it without changing the visible saved value.

No transaction is held across a network request, and this feature performs no
request.

## Platform behavior

The feature uses shared Drift, Riverpod, and Material code on Android, iOS,
Windows, macOS, and Linux. The list is scrollable and virtualized on every
platform, constrains readable width on larger windows, and uses native adaptive
switch visuals. It adds no native configuration.

## Security and privacy

Preferences, course labels, and counts remain in local SQLite. Credentials
remain in secure storage and are never read by this feature. The route issues
no backend request. Public error and debug representations exclude exception
messages, course labels, IDs, and assignment content.

Unknown courses and local-storage failures suppress effect policy. This
fail-closed boundary prevents a future notification or background worker from
assuming permission when local policy cannot be verified.

## Decisions

- Count current post-baseline identities rather than inventing unread state.
- Use the backend-supplied saved `due_date_exceed` flag rather than guessing
  timezone or completion semantics.
- Store preferences independently of the current course snapshot.
- Fence writes against both the active semester and current course row.
- Let absent preference rows inherit explicit defaults.
- Keep background preference enforcement after the shared snapshot download.
- Return direct mapped Drift watch streams; an extra asynchronous-generator
  wrapper delayed committed transaction emissions in tests.
- Use pessimistic row updates so the displayed switch is always saved state.
- Use one flat virtualized ledger instead of nesting scrolling card lists.

## Alternatives rejected

- An unread badge would require durable read-state semantics not owned here.
- Hashing course names would be less stable than the verified numeric course
  ID.
- A course foreign key would delete user intent whenever snapshot
  reconciliation removes a course.
- Optimistic switches could show values that were never committed.
- Per-course backend requests or snapshot filtering would invent unsupported
  transport behavior.
- Live deadline parsing would guess timezone and deadline semantics.

## Failure behavior

Initialization or watch failures show a redacted retry surface and change no
settings. Write exceptions map to a generic failure; stale semester/course
keys map separately. Both retain the previous preference. Invalid identifiers
fail at the store boundary.

Policy reads fail closed: unavailable storage and unknown current courses
allow neither notification nor background effect. A missing preference for a
known current course uses the documented defaults.

## Tests

Tests cover:

- Fresh schema shape, constraints, defaults, credential-column scan, and real
  v1/v2/v3/v4/v5/v6-to-v7 migration. The frozen v6 case preserves a connected
  graph spanning every historical v6 table before creating the empty
  preference table.
- Exact catalog counts, active-semester isolation, deterministic ordering,
  default preferences, stream updates after a committed transaction, stale
  write fencing, preservation across course removal/reappearance, and no
  network construction.
- Success, stale, exception mapping, missing-row defaults, muted/background
  policy combinations, fail-closed storage/unknown-course behavior, and
  immutable background-course sets.
- Loading, no-active, empty, stream error/retry, pending, success, stale and
  failed-write UI states.
- Semantic labels/actions, light/dark themes, reduced motion, 200% text at
  320/375/414/768/1200 logical pixels, and lazy large-list construction.
- Route provider loading, redacted initialization failure, retry, real shell
  reachability, and expired-session banner coexistence.
- Adaptive-shell resizing, pointer, keyboard, scaling, and session-state tests
  against a deterministic local course catalog.

## Validation evidence

The focused schema, migration, store, service, and policy suite passed 48/48.
The exact frozen v6-to-v7 case independently passed with all thirteen prior
tables seeded or configured and every row category re-read after migration.
The focused page suite passed 13/13. The combined course widget, provider, and
router coverage accounts for 43 passing tests after route initialization and
stale-write coverage were added.
The adaptive-shell suite passed 29/29 after its former placeholder harness was
updated for the real local route. Two generator passes completed; the second
skipped every input and wrote zero outputs. The strict format check covered
115 files with zero changes. Strict Dart and Flutter analysis reported no
issues. The full Flutter suite passed 437/437.
`flutter build linux --release` produced
`build/linux/x64/release/bundle/leb2-watch`. Diff and secret-scan evidence is
recorded in the worker handoff.

After independent review, the strengthened file-backed migration suite passed
12/12 and the full suite remained 437/437. Final formatting and both strict
analyzers passed, the Linux release build succeeded, and generated database
hashes remained unchanged.

## Known limitations

- Post-baseline activity count is durable discovery state, not unread state.
- Upcoming count reflects the last saved backend fields and does not update
  with the wall clock between synchronizations.
- Course identity and preferences remain semester-scoped, matching the
  existing cache; they are not partitioned by LEB2 user ID.
- Disabling background monitoring does not avoid the semester-wide snapshot
  request.
- Feature 12.2 consumes notification mute in the same transaction as its
  durable new-assignment decision. Background consumers remain unimplemented.
- Android, iOS, macOS, and Windows native builds are not verified on this
  Linux host.

## Future considerations

- Feature 12.2 transactionally re-reads the course and
  `notifications_muted`; muted discoveries are consumed without a platform
  call and do not surface after unmuting.
- Feature 13 background scheduling should use
  `readBackgroundMonitoredCourses` for post-download effects.
- A separately designed read-state feature could add a true unread count.
- Account partitioning requires a deliberate cache-wide migration rather than
  a course-only change.

## Related contexts

- [Local Database](local-database.md)
- [Adaptive Application Shell](adaptive-app-shell.md)
- [Assignment Diffing](assignment-diffing.md)
- [Semester Selection](semester-selection.md)
- [New-Assignment Notifications](new-assignment-notifications.md)
