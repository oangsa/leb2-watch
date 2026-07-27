# Android Native Local-Data Deletion Validation

## Status

Completed for the bounded disposable-emulator smoke; broader Android deletion
behavior remains partial.

## Purpose

Record native evidence that the production delete-all composition can remove
only LEB2 Watch-owned local test data on Android without a backend, user
account, or real credentials.

## Scope

- Android API 36 disposable-emulator integration smoke.
- Compile-time destructive-test guard, inert secure-store/database/cache
  sentinels, production delete-all adapters, and best-effort `finally`
  cleanup.
- Postcondition checks for the two application-owned secure-store values,
  exact SQLite artifacts, owned cache child, and a fresh database.
- Successful notification and WorkManager cancellation invocation.

## Non-scope

- Backend requests, session verification, assignments, real credentials,
  visible notification removal, WorkManager durable/in-flight cancellation,
  Keystore forensics, reboot/force-stop, and physical/OEM testing.

## User-visible behavior

None. This is an opt-in validation test, not a product control or runtime
flag. It cannot run unless the compile-time opt-in is affirmative and the
target is Android.

## Architecture

`android_local_data_deletion_runtime_test.dart` composes
`LocalDataDeletionCoordinator` with the production secure credential store,
Drift manager/storage cleanup, quiescence-aware local notification service,
Android WorkManager scheduler, cache cleanup, and unsupported mobile
autostart adapter. It seeds deterministic inert values only after the guard
passes. `deleteAll()` retains the normal deletion gate and native adapter
calls; `finally` repeats bounded cleanup if an assertion or platform call
fails.

## Important files

- `integration_test/android_local_data_deletion_runtime_test.dart` — guarded
  emulator smoke and bounded cleanup.
- `integration_test/support/android_native_local_data_deletion_guard.dart` —
  compile-time Android/opt-in gate.
- `test/platform/android/android_native_local_data_deletion_guard_test.dart` —
  guard truth-table coverage.
- `lib/src/features/settings/data_deletion/data/local_data_cleanup_adapters.dart`
  — production adapters under test.

## Contracts and interfaces

The integration test requires both:

```text
target platform: Android
LEB2_WATCH_DESTRUCTIVE_LOCAL_DATA_TEST=true
```

It does not send a request or import a backend client. The run uses the
non-routable documentation origin `https://backend.example.invalid` only to
satisfy app configuration; no source reads or calls it.

## Data model

The smoke creates no semester, course, activity, assignment, or user row. It
opens the existing schema and validates that a fresh reopen has no
`app_settings` row. The two secure-store sentinel values are deterministic and
non-authenticating.

## State and control flow

1. Guard rejects non-Android or missing opt-in before any write.
2. The test writes two inert secure-store values and one owned cache sentinel.
3. The production coordinator quiesces activity, cancels supported effects,
   clears credentials, scrubs/closes/deletes SQLite files, clears the owned
   cache, resets providers, and releases the gate.
4. The test reads only fixed postconditions, then opens/closes a fresh empty
   database.
5. `finally` independently retries only bounded app-owned cleanup calls.

## Platform behavior

On the disposable API 36 emulator, the smoke passed. Android autostart
correctly reported `notApplicable`. Native notification `cancelAll` and the
exact-name WorkManager cancellation call returned successfully. These are
invocation results, not durable operating-system receipts.

## Security and privacy

No real credential, backend response, user data, signing material, private
path, notification payload, screenshot, dump, or log inspection is used. The
test never requests notification permission and deletes only the app's two
namespaced secure-store keys, exact SQLite files, and the owned cache child.

## Decisions

- Use a compile-time opt-in rather than an environment/runtime switch so the
  destructive operation cannot run in ordinary host tests.
- Reuse production ports rather than create test-only deletion behavior.
- Treat plugin Future success as invocation evidence only.

## Alternatives rejected

- Package-wide data clearing or Android Keystore inspection: too broad and
  not necessary to prove application ownership boundaries.
- Scheduling a visible notification or registering periodic work: would add
  unrelated permission/timing state without strengthening deletion proof.
- Claiming WorkManager status or notification-manager state as durable OS
  proof: neither is justified by this run.

## Failure behavior

Guard failure happens before sentinel creation. Once started, independent
cleanup in `finally` preserves the original failure and makes bounded cleanup
attempts. A failed cleanup is a test failure, not a success claim.

## Tests

- Guard truth table: focused host test passed.
- Guarded integration smoke: one Android API 36 emulator test passed.

## Validation evidence

```text
flutter test test/platform/android/android_native_local_data_deletion_guard_test.dart
1 passed

dart analyze integration_test/android_local_data_deletion_runtime_test.dart \
  integration_test/support/android_native_local_data_deletion_guard.dart \
  test/platform/android/android_native_local_data_deletion_guard_test.dart
No issues found

flutter test -d emulator-5554 \
  integration_test/android_local_data_deletion_runtime_test.dart \
  --dart-define=LEB2_WATCH_DESTRUCTIVE_LOCAL_DATA_TEST=true \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid
1 passed
```

## Known limitations

- The smoke does not prove Android visibly removed notifications.
- It does not prove WorkManager cancellation is durable, stops active work, or
  survives reboot/force-stop.
- Direct secure-store reads are not forensic Android Keystore erasure proof.
- No physical device, OEM policy, backend/session, or user-flow navigation was
  exercised.

## Future considerations

Use a sanitized compatible backend fixture to validate baseline, session
expiry, scheduling, and end-to-end delete-all flow separately. Validate
durability and OEM behavior on physical Android devices.

## Related contexts

- [Local data deletion](local-data-deletion.md)
- [Android background synchronization](android-background-sync.md)
- [Platform build validation](platform-build-validation.md)
- [Public-beta readiness audit](public-beta-readiness-audit.md)
