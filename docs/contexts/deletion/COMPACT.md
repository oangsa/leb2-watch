# Deletion — Compacted Context

## Status

Completed. Delete-all now reports a separate installation-identity step:
Android is not applicable, while the app-owned non-Android secure-storage
value is removed and any failure keeps the bounded result incomplete.

## Purpose

Compacted context for the deletion feature area. Consolidated from historical records.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

`LocalDataDeletionService` — application-owned interface.
`LocalDataDeletionCoordinator` — serializes ops, converts port results to fixed `LocalDataDeletionStepResult`.
Ports: background work, autostart, notifications, credentials, installation
identity, DB cleanup, app cache, provider reset.
Platform/storage adapters: `data/local_data_cleanup_adapters.dart`.

`AppDatabaseManager` — owns foreground `AppDatabase`, exposes serialized awaited open/close.
Does not clear connection until executor close succeeds. Close failure permanently fails that
manager instance (closed-safe); cannot report false quiescence or open second connection.
`appDatabaseProvider` reads through manager, closes DB that finishes opening after disposal.
Provider reset invalidates `appDatabaseProvider` without recreating SQLite files; next consumer
opens on demand.

Production DB open obtains process-owned `lease-<pid>-<48-hex-token>` from `LocalDatabaseAccessGate`.
Entering deletion creates `owner-<pid>`, atomically renames fixed active-access dir to fixed
deleting dir. Opens completed before rename captured as leases; opens racing after rename abort
before Drift constructed. New process prunes only well-formed leases and owner markers identifying
different process. Current-process, malformed, unrelated entries preserved fail-closed. Full
deletion retains known foreground connection long enough for logical scrub, close…

### State and control flow

1. User triggers action → coordinator serialized gate.
2. If same operation in progress, join existing future.
3. Cancel background schedules → native fallback.
4. Cancel desktop autostart (if supported/enabled).
5. Cancel local notifications (await plugin call, cancel OS state after).
6. Cancel active syncs → fence under session mutation gate.
7. Cancel exact-revision automatic recovery under session mutation gate.
8. Enter cross-isolate DB/runtime gate: create `owner-<pid>`, rename active-access → deleting.
9. Await foreground close → bounded headless quiescence.
10. Logical scrub → delete SQLite main/-wal/-shm → delete `<application-cache>/leb2_watch`.
11. Cancel deletion-exclusive notifications.
12. Reset providers → invalidate `appDatabaseProvider`.
13. Clear secure credentials (credential-only or delete-all).
14. On delete-all, clear the app-owned non-Android installation identity;
    Android `ANDROID_ID` returns not-applicable.
15. Navigate to appropriate screen (semester selection / auth / onboarding).
16. Report fixed, redacted results; offer retry on partial.

If the bounded activity-quiescence wait times out, deletion is fail-closed:
record failed `activeOperations`/notification results and skip physical database
deletion, provider reset, and navigation (as well as deletion-owned
notification cancellation). The gate remains retained; when the old activity
settles, a retry reuses that gate, completes cancellation and cleanup, and can
restore normal admission. Limited logical scrub, credential cleanup, and owned
cache cleanup may still be reported as partial work, but never as complete
delete-all.

## Important Files

### Important files

- `lib/src/local_data_deletion/local_data_deletion_service.dart` — public interface
- `lib/src/local_data_deletion/local_data_deletion_coordinator.dart` — serialization logic
- `lib/src/local_data_deletion/local_data_deletion_step_result.dart` — fixed result type
- `lib/src/local_data_deletion/local_data_cleanup_adapters.dart` — platform/storage adapters
- `lib/src/local_data_deletion/local_data_deletion_activity_gate.dart` — cross-isolate gate
- `lib/src/local_data_deletion/local_data_deletion_notification_gate.dart` — notification gate
- `lib/src/local_data_deletion/local_data_deletion_provider_reset.dart` — provider reset
- `lib/src/local_data_deletion/local_database_access_gate.dart` — lease/gate protocol
- `lib/src/database/app_database_manager.dart` — foreground DB open/close
- `lib/src/database/app_database.dart` — Drift database
- `lib/src/local_data_deletion/local_data_deletion_step_result_test.dart` — step result tests
- `lib/src/local_data_deletion/local_data_deletion_activity_gate_test.dart` — activity gate tests
- `lib/src/local_data_deletion/local_data_deletion_notification_gate_test.dart` — notification gate tests
- `lib/src/local_data_deletion/local_database_access_gate_test.dart` — lease/gate tests
- `integration_test/android_local_data_deletion_runtime_test.dart` — Android runtime smoke
- `integration_test/end_to_end_mocked_workflow_test.dart` — full mocked workflow

## Contracts and Interfaces

### Contracts and interfaces

- `LocalDataDeletionService` — single public entry point
- `LocalDataDeletionCoordinator` — serialization + port result → `LocalDataDeletionStepResult`
- `DeviceIdentityCleanup` — separate app-owned installation-identity cleanup; it never uses `CredentialStore`
- `LocalDataDeletionStepResult` — fixed, redacted result type (no raw exceptions/paths/credentials)
- `LocalDatabaseAccessGate` — lease protocol: `lease-<pid>-<48-hex-token>`, `owner-<pid>`, `deleting` dir
- `AppDatabaseManager` — serialized open/close, fail-closed on close failure
- `appDatabaseProvider` — read-through, closes after disposal, invalidates on reset

## Decisions

### Decisions

- Serialized coordinator prevents race between concurrent deletion requests.
- Lease/gate protocol (not file deletion) for DB access safety — handles same-PID stale gates,
  OS PID reuse, and cross-process races.
- Provider invalidation (not eager recreation) — next consumer opens on demand.
- Fixed `LocalDataDeletionStepResult` — bounded output, no raw leak.
- Logout and Delete saved credentials preserve installation identity. Delete-all
  removes the non-Android secure-storage value and reports failure if owned
  identity deletion fails; Android cleanup is not applicable.

## Known Limitations

### Known limitations

- WorkManager/BGTask cancellation: best effort, cannot forcibly stop running native work.
- Native notification plugin call: cannot be forcibly cancelled once started.
- Same-PID stale gate: fail-closed (cannot distinguish from live owner).
- OS PID reuse: fail-closed.
- Different-PID stale gate: recovered under one active app-process model.
- Unpackaged Windows: cannot remove already-presented notifications.
- Android smoke: proves plugin-call completion only; cannot prove visible notification removal,
  WorkManager durability, or forensic Keystore erasure.
- Only Linux native build and bounded Android emulator smoke available on this host.

## Validation Evidence

### Tests

- Current review correction: device-identity cleanup, deletion-result,
  logout-preservation, and notification-route regressions are covered. The
  full runner discovered 149 test files across 15 sequential shards and all
  passed.
- `flutter test` — 904 tests passed after review corrections.
- Step result tests — 18 tests (gate/sync/notification group).
- Activity/deletion/provider composition — 48 tests.
- `LocalDatabaseAccessGate` test — Android + opt-in truth table.
- Android runtime smoke (emulator-5554, API 36) — plugin-call completion, null secure-store reads,
  absent SQLite files after fresh reopen, absent cache dir, empty `app_settings`.
- End-to-end mocked workflow — full delete-all, fresh DB defaults, return to onboarding.

### Validation evidence

- Current review correction (2026-08-03): Dart and Flutter analysis reported
  no issues; Dart formatting changed no files. The documented Android APK
  command was attempted but could not start because this host has no Java
  installation (`JAVA_HOME`/`java` unavailable).
- `flutter test` — 904 passed.
- `dart analyze --fatal-infos --fatal-warnings` — no issues.
- `flutter analyze --fatal-infos --fatal-warnings` — no issues.
- `dart format --output=none --set-exit-if-changed .` — 299 files checked, 0 changed.
- `flutter build linux --release` — built `build/linux/x64/release/bundle/leb2-watch`.
- Scoped diff checks: no credential values or added logging.
- No code generation required (no generated model/Drift table/schema changes).

## Cross-links

- Related: [session](../session/COMPACT.md) — credential removal is part of session teardown
- Related: [platform-validation](../platform-validation/COMPACT.md) — Android native deletion validation

---

*Auto-compacted from 1 source files. Retained details are in this compact and its linked feature areas.*
