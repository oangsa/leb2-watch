# Android Background Synchronization

## Status

Partially completed. The Dart implementation and static Android configuration
are complete, and a sanitized signed Release APK now builds and cold-launches
on an API 36 x86_64 emulator. Periodic WorkManager execution remains
fixture-dependent and is not yet end-to-end validated.

## Purpose

Run the existing local-first assignment synchronization periodically on
Android when the operating system permits, without a foreground service,
duplicate schedules, credential-bearing task input, or a second retry policy.

## Scope

- One unique 15-minute WorkManager periodic task.
- Connected-network constraint and stable persisted initial jitter.
- Android scheduling, cancellation, and scheduled-state queries behind the
  Feature 13.1 platform interface.
- A retained top-level callback dispatcher.
- Fresh headless application composition for every task execution.
- A fresh opaque 128-bit generation tag on each periodic registration.
- Generation-scoped headless cancellation for disabled and session-paused
  results.
- Shared, iOS-neutral WorkManager gateway and exact-name dispatcher seams.
- Release-inherited Android internet permission and static configuration tests.

## Non-scope

- Exact-time execution.
- Foreground services, custom Android workers, daemons, or permission prompts.
- iOS background task registration.
- Changes to synchronization, notification, credential, or database contracts.
- End-to-end WorkManager execution, notification delivery, or physical-device
  validation using a real or invented LEB2 session.

## User-visible behavior

When monitoring is enabled and the session/target/course gates allow it, Android
has one best-effort periodic assignment check. Android may delay or skip work
because of Doze, standby, battery policy, connectivity, OEM policy, or
force-stop. Cached data remains authoritative and visible if a task is delayed
or fails.

Disabling monitoring cancels only LEB2 Watch's unique periodic work. Background
execution never requests notification permission.

If a headless run observes that monitoring is disabled or its session is
paused, the durable local gate prevents HTTP and the callback submits
cancellation for only the opaque generation that invoked it. A stale callback
cannot cancel work registered after monitoring is enabled or a verified session
becomes active. Missing-target and no-background-course results remain handled
local no-ops and deliberately retain the chain because their current recovery
paths do not reconcile native scheduling.

## Architecture

`LocalBackgroundScheduler` owns the persisted monitoring preference and stable
per-install jitter. It passes the 15-minute cadence and stored delay to
`AndroidWorkmanagerSchedulerPlatform`, which translates the request through
the application-owned `WorkmanagerGateway`.

The WorkManager-created isolate invokes
`androidBackgroundCallbackDispatcher`. The shared exact-name dispatcher accepts
only `leb2-periodic-sync-v1`, supplies a nine-minute execution budget, and calls
`AndroidBackgroundSyncTaskHandler`. The handler creates a
`BackgroundSyncTaskExecutor` with a fresh
`ProviderBackgroundSyncCompositionFactory`. Feature 13.1 opens a new database
and provider container, reads the current local target and session policy,
and performs one `SyncReason.backgroundTask` synchronization. Owned resources
close only after that synchronization is terminal; a budget-triggered
cancellation whose request or synchronization does not settle within the
shared one-second drain remains retained in a close-after-quiescence
continuation until both settle.

Every actual registration generates a fresh 16-byte secure random token,
formats it as a strict lowercase-hex application tag, and stores that same tag
as the request tag and as the request's single application input value. The
dispatcher forwards the captured input map to the exact task handler without
including it in debug output.

The callback maps every durable `BackgroundSyncRunResult` to handled.
`BackgroundSyncDisabled` and `BackgroundSyncSessionPaused` validate the
captured tag and submit `cancelByTag`; all other results keep the chain.
Unexpected execution and cancellation-submission errors are handled without
native retry or sensitive logging, so application synchronization backoff stays
authoritative.

## Important files

- `lib/src/platform/background/android/android_workmanager_contract.dart` —
  stable work names, cadence floor, and execution budget.
- `lib/src/platform/background/android/android_workmanager_scheduler_platform.dart`
  — Android implementation of the shared scheduler platform.
- `lib/src/platform/background/android/android_background_callback.dart` —
  retained callback and headless task handler.
- `lib/src/platform/background/workmanager/workmanager_gateway.dart` —
  plugin boundary and periodic-request value object.
- `lib/src/platform/background/workmanager/workmanager_task_dispatcher.dart` —
  exact-name dispatch and cancellation/budget context.
- `lib/src/platform/background/families/android_background_scheduler_factory.dart`
  — Android family selection.
- `android/app/src/main/AndroidManifest.xml` — internet permission inherited by
  release builds.
- `android/app/proguard-rules.pro` — keeps Room database implementation
  constructors that Room loads reflectively after Release shrinking.
- `test/platform/background/android/` — Android scheduling, callback, and
  manifest coverage.
- `test/platform/android/android_release_signing_configuration_test.dart` —
  release-signing and narrow Room shrinker-rule regression coverage.
- `test/platform/background/workmanager/` — shared dispatcher coverage.

## Contracts and interfaces

The stable native contract is:

```text
unique work name: dev.oangsa.leb2watch.periodic-sync.v1
task name:        leb2-periodic-sync-v1
frequency:        15 minutes
network:          connected
existing policy:  update
tag:              dev.oangsa.leb2watch.periodic-sync.generation-v1.<32 hex>
input key:        dev.oangsa.leb2watch.periodic-sync.generation-tag-v1
input value:      the same opaque generation tag
```

`WorkmanagerGateway` exposes initialization, callback binding, periodic
registration, unique-name cancellation, tag cancellation, and an Android
scheduled-state query.
`WorkmanagerTaskDispatcher` maps exact task names to handlers. Its explicit
`retry` result is available for a future proven transient pre-bootstrap failure;
the Android assignment task does not use it.

## Data model

No Android-specific table or credential field was added. Monitoring state and
stable jitter remain in the Feature 13.1
`background_schedule_settings` row. Active semester, user identity, session
state, and course policies are read from local SQLite at execution time.
Credentials remain in operating-system secure storage. WorkManager stores only
the opaque generation tag; no semester ID, user ID, session revision, cookie,
username, password, backend URL, or response data enters the request.

## State and control flow

1. The foreground scheduler initializes WorkManager with the retained callback.
2. Enabling or reconciling monitoring creates a fresh generation tag and
   registers the same unique periodic work with
   `ExistingPeriodicWorkPolicy.update`.
3. WorkManager waits for Android scheduling and connected-network constraints.
4. The background isolate dispatches only the exact registered task name.
5. A fresh owned composition reads current local policy and runs one background
   synchronization.
6. The existing synchronization layer persists snapshots transactionally and
   applies notification/reminder effects only after commit.
7. Owned resources close after normal completion/failure or cancellation
   quiescence, never merely because cancellation was requested.
8. Every durable result is reported handled. Disabled and session-paused runs
   stop before HTTP and submit cancellation only for their captured generation.
   Missing-target and no-background-course results stop before HTTP and leave
   the chain available for later recovery.

Repeated initialization joins one in-flight initialization. Repeated
registration cannot create a second unique name. Explicit foreground disable
and foreground session reconciliation use `cancelByUniqueName`; they never call
`cancelAll`.

With pinned AndroidX WorkManager 2.10.2, `UPDATE` and tag cancellation use
WorkManager's serial task executor. Updating a periodic WorkSpec replaces its
old tags and input in the same transaction. If old-tag cancellation runs first,
the later update re-enqueues the fresh generation; if update runs first, the old
tag lookup no longer matches. Either ordering preserves the newer registration.
The pinned Flutter plugin discards Android's returned `Operation`, so a
completed Dart future proves submission without a synchronous/plugin error,
not native terminal state.

## Platform behavior

Android WorkManager execution is periodic and best effort, with a platform
minimum interval of 15 minutes. The scheduled status reports active/inactive,
but no exact next check. Normal app restarts and device reboot are handled by
WorkManager's durable schedule. A force-stopped app cannot resume itself until
the user opens it again.

Other platform adapters remain owned by their respective features. The shared
gateway and dispatcher are platform-neutral so the iOS implementation can
reuse them with its own top-level entrypoint and task names.

The final merged Release manifest also contains AndroidX WorkManager 2.10.2's
transitive `android.permission.FOREGROUND_SERVICE` declaration and
`androidx.work.impl.foreground.SystemForegroundService`. LEB2 Watch adds no
app-owned foreground-service declaration, custom worker, foreground request,
or continuously running service: it registers ordinary non-expedited periodic
work only. This provenance is an artifact fact, not a claim that the final
manifest has no foreground-service component at all.

## Security and privacy

- WorkManager input contains exactly one opaque random generation tag that is
  also used as the WorkRequest tag.
- Session cookies, usernames, passwords, semester IDs, user IDs, headers, and
  response bodies are not registered with or logged by WorkManager.
- Diagnostic `toString` values are redacted.
- The background callback never requests notification permission.
- No app-owned foreground service, custom worker, analytics, crash reporting,
  or remote persistence was introduced. AndroidX WorkManager's transitive
  foreground-service declaration is documented under Platform behavior.

## Decisions

- Use one stable unique work name with `update` so re-registration changes the
  specification without duplicating jobs.
- Generate a fresh 128-bit tag for every actual registration and validate the
  captured prefix, length, lowercase-hex encoding, and type before cancellation.
- Forward Feature 13.1's persisted jitter as `initialDelay`; the Android layer
  does not generate randomness.
- Use only a connected-network constraint because charging, idle, unmetered,
  and exact-time requirements are not product contracts.
- Keep the nine-minute Dart budget below WorkManager's ordinary ten-minute
  execution limit.
- Return native success for every durable application outcome. Durable local
  gates and application backoff remain authoritative.
- Cancel only the captured generation for disabled and session-paused results.
  Fresh per-registration tags prevent an old result from cancelling recovered
  work under the stable unique name.
- Keep missing-target and no-background-course results scheduled because
  semester selection and per-course preference changes do not currently
  reconcile the native schedule.
- Let explicit foreground disable and foreground session reconciliation own
  cancellation and recovery registration.
- Return native success for unknown task names and unexpected handler errors to
  avoid deterministic retry loops or stacked backoff.
- Preserve `RoomDatabase` zero-argument constructors in Release shrinking.
  Room 2.6.1 creates generated database implementations reflectively; without
  this narrow rule, R8 removed `WorkDatabase_Impl.<init>()` and the AndroidX
  WorkManager startup provider crashed before Flutter could render.

## Alternatives rejected

- `ExistingPeriodicWorkPolicy.keep` would retain stale constraints or cadence.
- Deprecated replacement semantics would reset existing scheduling state.
- `cancelAll` could cancel work owned by another feature or plugin.
- Credential-bearing task input would become stale and violate the privacy
  model.
- A foreground service or custom native worker adds lifecycle and permission
  costs without being required for periodic synchronization.
- Returning native retry for every failed synchronization would stack Android
  backoff on the existing durable 1m/2m/5m/15m application policy.
- Raw headless `cancelByUniqueName` would let a stale stop result cancel a newer
  valid replacement chain.
- WorkRequest ID and native integer generation are not exposed to Dart by the
  pinned plugin, and the WorkSpec ID is retained across `UPDATE`.
- Unique work names per registration would abandon the one-chain invariant and
  require durable enumeration across process death and reboot.
- A WorkDatabase-specific keep rule, a global no-shrink rule, or a broad
  keep-all-members rule would hide the actual Room reflection contract and
  retain more code than necessary.

## Failure behavior

Feature 13.1 maps platform initialization, registration, cancellation, status,
and local-storage errors into redacted scheduler statuses or exceptions.
Handled synchronization failures preserve valid cached data. Session expiration
pauses automatic synchronization without deleting cached assignments. Disabled
monitoring, missing targets, no-background-course policy, and session pause are
handled local no-ops that perform no HTTP. Disabled and session-paused results
submit scoped cancellation when their captured input is strictly valid.
Malformed or absent input, every other typed result, and unexpected exceptions
submit no cancellation. A cancellation submission failure is swallowed and
redacted; a later wake can resubmit the same tag-scoped request. No outcome asks
WorkManager for native retry.

Android can stop the process without running Dart cleanup. Durable database
leases, operation fencing, transactional persistence, notification history, and
later foreground reconciliation remain the recovery mechanisms.

## Tests

- `workmanager_task_dispatcher_test.dart` — exact-name dispatch, explicit retry,
  fail-closed handled behavior, captured-input propagation/redaction,
  cancellation, and execution budget.
- `android_workmanager_scheduler_platform_test.dart` — joined initialization,
  stable names, 15-minute floor, persisted delay forwarding, connected network,
  update policy, fresh strict generation tags/input, unique cancellation, and
  status.
- `android_background_callback_test.dart` — handled mapping for every durable
  result, strict malformed-input rejection, cancellation-submission failure,
  background reason/budget, unexpected-error behavior, retained entrypoint
  wiring without unique-name cancellation, and deterministic cancel-before-
  update/update-before-stale-cancel recovery interleavings.
- `android_manifest_configuration_test.dart` — internet permission, preserved
  boot/notification/backup configuration, and absence of foreground service,
  custom initializer, or exact-alarm additions.
- `local_background_scheduler_test.dart` — preserves desired monitoring intent
  while a session is expired and registers exactly one fresh schedule after
  verified activation.
- `android_release_signing_configuration_test.dart` — confirms the narrow
  `RoomDatabase` constructor keep rule exists and rejects a
  `WorkDatabase_Impl`-specific, no-shrink, or broad keep-all workaround.

## Validation evidence

The generation-scoped pause change was validated on Flutter 3.44.8 and Dart
3.12.2 with serialized tests:

```text
flutter test --concurrency=1 \
  test/platform/background/workmanager/workmanager_task_dispatcher_test.dart \
  test/platform/background/android/android_workmanager_scheduler_platform_test.dart \
  test/platform/background/android/android_background_callback_test.dart \
  test/platform/background/ios_background_scheduler_platform_test.dart
24 tests passed

flutter test --concurrency=1 \
  test/platform/background/workmanager/workmanager_task_dispatcher_test.dart \
  test/platform/background/android/android_workmanager_scheduler_platform_test.dart \
  test/platform/background/android/android_background_callback_test.dart \
  test/platform/background/ios_background_scheduler_platform_test.dart \
  test/platform/background/ios_background_callback_test.dart \
  test/features/background_sync/application/background_sync_runner_test.dart \
  test/features/background_sync/application/local_background_scheduler_test.dart \
  test/features/settings/data_deletion/application/local_data_deletion_service_test.dart \
  test/features/authentication/application/automatic_session_reauthentication_service_test.dart \
  test/features/authentication/application/reauthenticating_assignment_sync_service_test.dart \
  test/app/provider_background_sync_composition_test.dart
78 tests passed

dart format --output=none --set-exit-if-changed .
Formatted 316 files; 0 changed

dart analyze --fatal-infos --fatal-warnings .
No issues found

flutter analyze --fatal-infos --fatal-warnings
No issues found

flutter test --concurrency=1
1009 tests passed

git diff --check
Passed
```

### Native Android release validation — 2026-07-27

This host now has a user-owned Android SDK, a user-owned JDK 17, hardware
accelerated emulator support, and an API 36 Google APIs x86_64 AVD. `flutter
doctor` reported a working Android toolchain. The emulator, SDK, and the
external test-only signing identity remain outside the repository.

The build gate was deliberately exercised in both modes with sanitized
production configuration:

```text
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<SANITIZED_BACKEND_ORIGIN>
```

- With no local signing configuration, the generated APK was intentionally
  unsigned; `apksigner verify` failed as expected because it had no manifest
  signature.
- With a complete ignored `android/key.properties` that referenced an external
  test-only identity, the Release APK verified with a v2 signature. The final
  repaired artifact was SHA-256
  `527b5d28dd3a525e005d7c83b6cbcaf545e28e14ebcbc793a6e679589b054103`.
  That identity is validation-only, not a production or distribution key.
- The initial signed build exposed a real Release-only startup defect:
  WorkManager's startup provider failed with
  `NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init>[]`.
  R8's usage output and the final dex confirmed that the reflective Room
  constructor had been removed. Adding the narrow `RoomDatabase` constructor
  rule above retained it in the final dex.
- The repaired signed APK installed with `adb install -r --no-streaming` on
  the API 36 AVD. A cold launch reached `MainActivity` in 723 ms without the
  WorkDatabase crash. A force-stop and second launch reached the local
  `Connect LEB2` screen in 709 ms.

The native walk-through rendered onboarding through session setup without
entering credentials or granting a permission. It visually and semantically
confirmed the independent-third-party disclaimer, local SQLite/secure-storage
explanation, temporary backend-request explanation, and notification purpose
explanation before any notification prompt. Clean startup logs contained no
authorization header, bearer token, session cookie, or password value.

Focused host validation after the repair passed:

```text
flutter test --concurrency=1 \
  test/platform/android/android_release_signing_configuration_test.dart \
  test/platform/background/android/android_manifest_configuration_test.dart \
  test/platform/background/android/android_workmanager_scheduler_platform_test.dart \
  test/platform/background/android/android_background_callback_test.dart \
  test/platform/local_notifications_native_config_test.dart \
  test/core/security/secure_storage_platform_configuration_test.dart
32 tests passed

dart format --output=none --set-exit-if-changed .
Formatted 330 files; 0 changed

dart analyze --fatal-infos --fatal-warnings
No issues found

flutter analyze --fatal-infos --fatal-warnings
No issues found
```

Persisted current-suite output proves the memory-safe host runner discovered
132 test files and completed all 14 sequential shards. Every shard emitted its
Flutter success marker, totaling 1,097 passed test cases. The wrapper command's
explicit shell exit code was not captured in the persisted output and is not
claimed. Separate final-validation logs also prove repository formatting
(`330` files, `0` changed, exit `0`), strict Dart analysis (no issues, exit
`0`), strict Flutter analysis (no issues, exit `0`), and `git diff --check`
(exit `0`). The earlier SDK-cache sandbox blocker is resolved for this
validation pass; fixture/session-dependent native behavior remains unproven.

The callback test was introduced red: the handler did not accept scoped
cancellation and the request had no generation tag/input. The focused green
pass covers both serialized WorkManager operation orderings. These Dart tests
do not prove Android runtime or native `Operation` completion.

## Known limitations

- A verified sanitized backend fixture, session, semester, and course have not
  been supplied. Therefore this validation does not prove native unique-work
  registration/execution, network constraints, baseline/diff notification
  behavior, session expiry/recovery, visible notification delivery, reminder
  rescheduling, secure-storage CRUD, or delete-all behavior.
- No notification permission was granted and no test notification was sent.
  The absence of a prompt during onboarding is proven; the OS permission state
  and delivery path are not.
- The AVD is an emulator-only result. USB device validation remains unrun; the
  host does not have the optional `android-udev` package installed.
- Reboot and force-stop recovery of a scheduled worker are untested. The
  observed force-stop/relaunch proves foreground startup only.

- A prior no-SDK host result is superseded by the 2026-07-27 Release build and
  emulator evidence above; it is not a current limitation.
- The Flutter plugin confirms cancellation submission but does not await
  Android's returned WorkManager `Operation`; process death in that narrow
  window can leave the old generation scheduled until a later local-only wake
  resubmits cancellation.
- Missing-target and no-background-course headless states intentionally retain
  the periodic chain. Those wakes remain local no-ops and perform no HTTP.
- WorkManager does not expose a cooperative Dart cancellation callback when
  Android stops the worker; the execution-budget hook is the available
  cooperative bound.
- OEM battery restrictions and force-stop behavior require device validation.
- Notification delivery cannot be proven by a completed plugin future.

## Future considerations

With a verified sanitized fixture/session, inspect JobScheduler state and then
exercise offline constraints, repeated registration, permission denial,
process death, reboot, force-stop/reopen, session expiration, baseline silence,
and exactly-once notification behavior. For session expiration specifically,
exercise both operation orderings: old generation cancellation before
verified-session `UPDATE`, and verified-session `UPDATE` before stale
old-generation cancellation. Verify that only the fresh generation remains
scheduled after each ordering, including after process death and reboot.

## Related contexts

- `docs/contexts/background-scheduler.md`
- `docs/contexts/assignment-synchronization.md`
- `docs/contexts/synchronization-backoff.md`
- `docs/contexts/local-notifications.md`
- `docs/contexts/new-assignment-notifications.md`
- `docs/contexts/deadline-reminders.md`
