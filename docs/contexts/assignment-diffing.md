# Assignment Baseline and Change Detection

## Status

Completed for validated snapshot persistence, durable semester baselines, and
source-level new, deadline-changed, and removed assignment detection. No
notification plugin or operating-system reminder effect is part of this
feature.

## Purpose

Prevent historical assignments from being announced on first synchronization
while detecting later assignment changes exactly once per successful snapshot.
The result remains reconstructable for independent synchronization callers and
leaves durable work state for later local-notification features.

## Scope

- Explicit baselines for populated and empty first snapshots.
- Transactional current-snapshot reconciliation instead of delete-all
  replacement.
- Stable backend identities and a dormant versioned SHA-256 fallback policy.
- New-activity, deadline-changed, and removed change values.
- Operation-owned change rows for joined-result reconstruction.
- Durable seen, notification-history, and reminder reconciliation state.
- Schema v3 plus real file-backed v1-to-v3 and v2-to-v3 migrations.

## Non-scope

- Showing assignment notifications.
- Scheduling, cancelling, or rescheduling operating-system reminders.
- Computing reminder instants from unzoned backend dates.
- Exact overdue or deadline-inclusivity semantics.
- Retry/backoff, platform scheduling, providers, screens, or account
  partitioning.

## User-visible behavior

This feature adds no screen. The first successful snapshot for a semester,
including an empty snapshot, becomes a baseline and reports no historical
changes. Later successful snapshots report deterministic identity-and-kind
changes only after the complete database transaction commits. Repeated
snapshots do not report duplicates, and a previously seen assignment that
reappears is not treated as never seen.

Feature 10.2 reads current `seen_activities.is_baseline = false` rows as the
truthful per-course post-baseline activity count. It does not reinterpret that
durable discovery evidence as unread state.

## Architecture

`AssignmentSyncService` remains the small public seam. `SyncSuccess` now owns
one immutable `AssignmentChangeBatch`. `AssignmentSnapshotReconciler` is an
internal Drift-backed module that owns baseline lookup, diff computation,
snapshot upserts/deletes, seen-ledger updates, operation-change persistence,
and reminder flags. `SyncOperationStore` owns the fenced transaction and
asynchronous terminal-result reconstruction.

The reconciliation module has no public abstract adapter because only the
existing Drift transaction varies. Callers do not need to learn database
ordering or change-storage details.

## Important files

- `lib/src/features/assignments/sync/assignment_sync_service.dart` — public
  immutable/redacted change values.
- `lib/src/features/assignments/sync/assignment_snapshot_reconciler.dart` —
  transactional baseline, diff, and snapshot implementation.
- `lib/src/features/assignments/sync/activity_identity.dart` — backend identity,
  dormant fingerprint v1, and source-date canonicalization.
- `lib/src/features/assignments/sync/sync_operation_store.dart` — fenced
  completion and stored change-batch reconstruction.
- `lib/src/core/database/database_tables.dart` — v3 baseline, change, and
  reminder ownership schema.
- `lib/src/core/database/app_database.dart` — ordered v1/v2-to-v3 migration.
- `pubspec.yaml` and `pubspec.lock` — direct, locked SHA-256 implementation
  dependency (`crypto` 3.0.7).
- `test/features/assignments/sync/assignment_diffing_test.dart` — behavior,
  rollback, reminder, and independent-join tests.
- `test/features/assignments/sync/activity_identity_test.dart` — identity,
  canonicalization, immutability, and redaction tests.

## Contracts and interfaces

`AssignmentSyncService.synchronize` and `cancelCurrent` are unchanged.
Successful results add:

```dart
enum AssignmentChangeKind { newActivity, deadlineChanged, removed }

final class AssignmentChange {
  final String identityKey;
  final AssignmentChangeKind kind;
}

final class AssignmentChangeBatch {
  final List<AssignmentChange> changes;
}
```

Batches sort by fixed enum order and then identity, compare by value, expose an
unmodifiable list, and redact debug output. They contain no title,
description, payload, credential, response, or stack trace.

## Data model

Schema version 3 adds:

- `assignment_baselines`: one semester-owned row; row existence is
  authoritative. Fresh rows have `established_at_utc`; migrated rows may use
  null when the historical instant is unknowable.
- `sync_operation_changes`: operation/semester/identity/kind rows constrained
  to the three change kinds. Its composite operation/semester foreign key
  prevents evidence from crossing operation ownership, while the existing
  semester/identity foreign key preserves seen-ledger ownership. Operation
  deletion and seen-ledger deletion cascade these result-evidence rows.
- `scheduled_reminders.needs_reconciliation`: durable eventual-work flag.

Scheduled reminders now reference `seen_activities`, not current
`activities`. An unchanged reminder survives snapshot upsert; a deadline
change or removal retains its notification ID and sets the reconciliation
flag.

The course-preferences catalog reads current activities only. Its upcoming
count requires a non-null saved deadline source and `due_date_exceed = false`;
it does not parse source dates or apply a live clock.

## State and control flow

1. The fenced success transaction captures one UTC completion/observation time.
2. The reconciler reads the baseline, current activities, and seen identities.
3. Incoming courses and activities resolve to stable identities.
4. The first snapshot writes seen rows as baseline and emits no changes.
5. Later snapshots compare incoming identities with current and durable seen
   state.
6. Courses/activities are upserted; missing activities/courses are deleted
   last.
7. Deadline-changed and removed identities mark retained reminders pending.
8. The change batch is stored under the synchronization operation.
9. Success history and the terminal operation commit in the same transaction.
10. Every caller reconstructs the committed batch using both operation and
    semester IDs, so even a deliberately corrupted database cannot return
    foreign-semester evidence.

## Platform behavior

The Dart/SQLite implementation is shared by Android, iOS, Windows, macOS, and
Linux. Linux is the only native target build-verified on this host. No
platform-notification behavior was added.

## Security and privacy

Change rows retain only local operation ID, semester ID, stable assignment
identity, and a fixed kind. Public/debug values are redacted. The database
continues to contain no credential, cookie, password, authorization header, or
raw response archive. Fingerprint inputs exclude description, deadline,
submission data, attachments, questions, and raw JSON.

## Decisions

- Baseline row existence, not sync reason or seen-row count, decides whether a
  snapshot is historical.
- Current valid activities use `backend:<positive-id>`.
- Fingerprint v1 uses course ID, normalized activity type, whitespace-normalized
  title, and canonical created-at source with a version-tagged length-prefixed
  SHA-256 encoding.
- Deadline comparison accepts the verified signed four-to-six-digit-year
  grammar and Dart parser behavior, canonicalizes representational differences,
  but never assigns an unzoned source a timezone.
- Operation change rows are bounded result evidence; seen/reminder ledgers are
  the durable eventual-work sources.
- A named unique `(operation_id, semester_id)` parent index makes operation
  ownership enforceable by SQLite; result reads repeat both predicates as
  defense in depth.
- Reminder ownership moved to the seen ledger so removals retain cancellation
  identifiers for Feature 12.
- Mutable assignment payload fields cannot enter fingerprint v1 through the
  typed resolver interface. Behavior tests exercise every accepted fingerprint
  input instead of inspecting production source text.

## Alternatives rejected

- `seen_activities.is_baseline` alone cannot represent an empty baseline.
- Sync history is globally bounded and cannot be the authoritative marker.
- A sentinel assignment would invent an identity and course.
- Delete-all replacement destroys reminder rows and obscures exact removals.
- Raw response hashing, list indices, and mutable fields are unstable
  identities.
- A generic event bus would introduce acknowledgement semantics before an
  effect owner exists.
- Converting unzoned deadlines to UTC would invent a backend contract.

## Failure behavior

Transport failure or cancellation occurs before reconciliation and writes no
baseline/change/reminder state. Reconciliation, ledger, reminder, history, and
terminal-success writes share the fenced transaction; any failure rolls them
all back. The existing separate bounded `persistenceFailed` result then
terminalizes safely. Ambiguous duplicate identities fail instead of merging
assignments.

Invalid legacy date sources compare conservatively as exact strings. A stale
lease owner remains fenced from every reconciliation write.

## Tests

Tests cover:

- populated and empty first baselines;
- empty baseline followed by one new assignment;
- one later addition and identical snapshots;
- real and formatting-only deadline changes;
- signed/extended years, omitted/explicit seconds, fractional precision 1–9,
  positive/negative offsets, rollover, zoned/unzoned distinction, and invalid
  legacy source preservation;
- a formatting-only signed-year deadline change through the synchronization
  seam;
- stable assignment movement between courses with no change or reminder churn;
- removal, repeated removal, and seen-identity reappearance;
- changed, removed, and unchanged reminder behavior;
- retained seen and notification-history ledgers;
- rollback of snapshot, ledgers, changes, history success, and flags;
- ambiguous identity rejection;
- independent connection joiners receiving one equal batch;
- backend identity priority and deterministic fingerprint v1;
- behavioral contribution of every typed fingerprint input, with mutable/raw
  assignment payloads excluded by the resolver signature;
- conservative date canonicalization and batch immutability/redaction;
- schema tables, indices, composite operation/semester and seen-identity
  ownership, checks, cascades, collision backstop, and credential scan;
- cross-semester change rejection plus reader filtering under deliberate
  foreign-key-disabled corruption;
- real v1/v2 migrations, legacy baseline seeding, reminder preservation, and
  clean foreign-key checks.

## Validation evidence

The worker initialized Flutter/Dart through a newly opened zsh before the first
tool invocation, then used the resolved SDK path.

```text
flutter pub get
Passed; crypto remained at 3.0.7 and changed only from transitive to direct
main in pubspec.lock.

dart run build_runner build --delete-conflicting-outputs
Passed; the ownership-schema pass regenerated the live schema, a post-format
repeat reported two same outputs, and the final stability pass wrote 0 outputs.

dart format --output=none --set-exit-if-changed .
Passed; 75 files checked, 0 changed.

flutter test test/features/assignments/sync test/core/database test/core/network
Passed: 134 tests.

dart analyze
Passed: no issues.

flutter analyze
Passed: no issues.

flutter test
Passed: 234 tests.

flutter build linux --release
Passed: build/linux/x64/release/bundle/leb2-watch.
```

Secret, placeholder, TODO, changed-file, and context-heading scan evidence is
recorded in the worker handoff for this feature.

## Known limitations

- The backend contract does not define the timezone of unzoned deadlines or
  deadline inclusivity, so actual reminder instants remain blocked.
- Every verified current activity has a positive backend ID. Fingerprint v1 is
  dormant policy and has not processed a real valid transport response.
- Snapshot/baseline tables are semester-scoped while synchronization operations
  also carry user ID. A different account using the same semester could be
  compared with prior local data until session/account ownership defines reset
  or profile partitioning.
- A legacy successfully empty semester cannot be recognized if its bounded
  success history was already pruned and no current/seen row remains. Its next
  success safely becomes a silent baseline.
- Feature 8.1's standard lease limitation remains: fencing prevents stale
  persistence, but arbitrary suspension past lease expiry cannot prove that a
  second GET never occurred.

## Future considerations

- Feature 12.2 now consumes current non-baseline seen rows with durable
  notification-history deduplication after committed success.
- Reconcile and clear pending reminder rows in Feature 12.3 after timezone
  semantics are resolved.
- Define account-change ownership before allowing two users' semester caches to
  coexist.
- Activate the fallback path only after a verified transport contract permits a
  missing backend activity ID.

## Related contexts

- [Assignment Synchronization](assignment-synchronization.md)
- [Local Database](local-database.md)
- [Backend API Contract](backend-api-contract.md)
- [Backend API Client](backend-api-client.md)
- [New-Assignment Notifications](new-assignment-notifications.md)
- [API Error Mapping](api-error-mapping.md)
- [Course Preferences](course-preferences.md)
