# Android Background Synchronization

## Status

Completed at the Dart and static Android configuration level. An Android SDK,
emulator, or device was not available, so APK and runtime behavior remain
unverified.

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
- Shared, iOS-neutral WorkManager gateway and exact-name dispatcher seams.
- Release-inherited Android internet permission and static configuration tests.

## Non-scope

- Exact-time execution.
- Foreground services, custom Android workers, daemons, or permission prompts.
- iOS background task registration.
- Changes to synchronization, notification, credential, or database contracts.
- Native Android instrumentation or device validation on this host.

## User-visible behavior

When monitoring is enabled and the session/target/course gates allow it, Android
has one best-effort periodic assignment check. Android may delay or skip work
because of Doze, standby, battery policy, connectivity, OEM policy, or
force-stop. Cached data remains authoritative and visible if a task is delayed
or fails.

Disabling monitoring cancels only LEB2 Watch's unique periodic work. Background
execution never requests notification permission.

If a headless run observes that monitoring is disabled, its target is missing,
or its session is paused, the durable local gate prevents HTTP and the callback
reports the wake handled without mutating native scheduling. The periodic chain
can therefore remain scheduled and produce later local no-op wakes until policy
recovers. Explicit foreground disable and foreground session reconciliation
remain the owners of native cancellation and recovery registration.

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

The callback maps every durable `BackgroundSyncRunResult` to handled and has no
schedule-mutation capability. Unexpected execution errors are also handled
without native retry, so application synchronization backoff stays
authoritative. Keeping the headless callback schedule-neutral prevents a stale
stop result from cancelling a newer valid registration under the same stable
unique work name.

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
- `test/platform/background/android/` — Android scheduling, callback, and
  manifest coverage.
- `test/platform/background/workmanager/` — shared dispatcher coverage.

## Contracts and interfaces

The stable native contract is:

```text
unique work name: dev.oangsa.leb2watch.periodic-sync.v1
task name:        leb2-periodic-sync-v1
frequency:        15 minutes
network:          connected
existing policy:  update
input data:       none
```

`WorkmanagerGateway` exposes initialization, callback binding, periodic
registration, unique-name cancellation, and an Android scheduled-state query.
`WorkmanagerTaskDispatcher` maps exact task names to handlers. Its explicit
`retry` result is available for a future proven transient pre-bootstrap failure;
the Android assignment task does not use it.

## Data model

No Android-specific table or credential field was added. Monitoring state and
stable jitter remain in the Feature 13.1
`background_schedule_settings` row. Active semester, user identity, session
state, and course policies are read from local SQLite at execution time.
Credentials remain in operating-system secure storage and never enter
WorkManager input data.

## State and control flow

1. The foreground scheduler initializes WorkManager with the retained callback.
2. Enabling or reconciling monitoring registers the same unique periodic work
   with `ExistingPeriodicWorkPolicy.update`.
3. WorkManager waits for Android scheduling and connected-network constraints.
4. The background isolate dispatches only the exact registered task name.
5. A fresh owned composition reads current local policy and runs one background
   synchronization.
6. The existing synchronization layer persists snapshots transactionally and
   applies notification/reminder effects only after commit.
7. Owned resources close after normal completion/failure or cancellation
   quiescence, never merely because cancellation was requested.
8. Every durable result is reported handled. Disabled, missing-target, and
   session-paused runs stop before HTTP but leave the stable unique chain
   unchanged.

Repeated initialization joins one in-flight initialization. Repeated
registration cannot create a second unique name. Explicit foreground disable
and foreground session reconciliation use `cancelByUniqueName`; they never call
`cancelAll`. The pinned plugin completes its Dart method-channel call after
submitting `cancelUniqueWork`; it does not await Android's returned `Operation`.
A completed Dart future therefore proves request submission without a
synchronous/plugin error, not native terminal state.

## Platform behavior

Android WorkManager execution is periodic and best effort, with a platform
minimum interval of 15 minutes. The scheduled status reports active/inactive,
but no exact next check. Normal app restarts and device reboot are handled by
WorkManager's durable schedule. A force-stopped app cannot resume itself until
the user opens it again.

Other platform adapters remain owned by their respective features. The shared
gateway and dispatcher are platform-neutral so the iOS implementation can
reuse them with its own top-level entrypoint and task names.

## Security and privacy

- WorkManager input data is always absent.
- Session cookies, usernames, passwords, semester IDs, user IDs, headers, and
  response bodies are not registered with or logged by WorkManager.
- Diagnostic `toString` values are redacted.
- The background callback never requests notification permission.
- No foreground service, custom worker, analytics, crash reporting, or remote
  persistence was introduced.

## Decisions

- Use one stable unique work name with `update` so re-registration changes the
  specification without duplicating jobs.
- Forward Feature 13.1's persisted jitter as `initialDelay`; the Android layer
  does not generate randomness.
- Use only a connected-network constraint because charging, idle, unmetered,
  and exact-time requirements are not product contracts.
- Keep the nine-minute Dart budget below WorkManager's ordinary ten-minute
  execution limit.
- Return native success for every durable application outcome. Durable local
  gates and application backoff remain authoritative.
- Keep the headless callback schedule-neutral. A stop result reflects an
  earlier local policy snapshot and must not cancel a newer stable-name
  registration.
- Let explicit foreground disable and foreground session reconciliation own
  cancellation and recovery registration.
- Return native success for unknown task names and unexpected handler errors to
  avoid deterministic retry loops or stacked backoff.

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
  valid replacement chain. Race-safe terminal self-cancellation requires a
  future native-owned, generation-aware scheduling coordinator rather than a
  Dart read-then-cancel check.

## Failure behavior

Feature 13.1 maps platform initialization, registration, cancellation, status,
and local-storage errors into redacted scheduler statuses or exceptions.
Handled synchronization failures preserve valid cached data. Session expiration
pauses automatic synchronization without deleting cached assignments. Disabled
monitoring, missing targets, and session pause are handled local no-ops that
perform no HTTP. When these states are discovered only by a headless isolate,
the chain can remain scheduled and later wakes repeat the local gates until
policy recovers. All durable outcomes and unexpected execution exceptions are
handled without callback cancellation or native retry.

Android can stop the process without running Dart cleanup. Durable database
leases, operation fencing, transactional persistence, notification history, and
later foreground reconciliation remain the recovery mechanisms.

## Tests

- `workmanager_task_dispatcher_test.dart` — exact-name dispatch, explicit retry,
  fail-closed handled behavior, cancellation, and execution budget.
- `android_workmanager_scheduler_platform_test.dart` — joined initialization,
  stable names, 15-minute floor, persisted delay forwarding, connected network,
  update policy, unique cancellation, and status.
- `android_background_callback_test.dart` — handled mapping for every durable
  result, background reason/budget, unexpected-error behavior, retained
  entrypoint wiring without headless cancellation, and deterministic stale
  disabled/missing-target/session-paused replacement-survival interleavings.
- `android_manifest_configuration_test.dart` — internet permission, preserved
  boot/notification/backup configuration, and absence of foreground service,
  custom initializer, or exact-alarm additions.
- `local_background_scheduler_test.dart` — preserves desired monitoring intent
  while a session is expired and registers exactly one fresh schedule after
  verified activation.

## Validation evidence

Executed on Flutter 3.44.8 and Dart 3.12.2:

```text
flutter test --concurrency=1 \
  test/platform/background/android/android_background_callback_test.dart \
  test/platform/background/android/android_workmanager_scheduler_platform_test.dart \
  test/features/background_sync/application/local_background_scheduler_test.dart \
  test/features/background_sync/application/background_sync_runner_test.dart \
  test/platform/background/ios_background_callback_test.dart \
  test/platform/background/ios_background_configuration_test.dart \
  test/platform/desktop/desktop_native_configuration_test.dart
30 tests passed

dart analyze --fatal-infos --fatal-warnings \
  lib/src/platform/background/android/android_background_callback.dart \
  test/platform/background/android/android_background_callback_test.dart \
  test/platform/background/android/android_workmanager_scheduler_platform_test.dart \
  test/features/background_sync/application/local_background_scheduler_test.dart \
  test/features/background_sync/application/background_sync_runner_test.dart \
  test/platform/background/ios_background_callback_test.dart \
  test/platform/background/ios_background_configuration_test.dart \
  test/platform/desktop/desktop_native_configuration_test.dart
No issues found

dart format --output=none --set-exit-if-changed \
  lib/src/platform/background/android/android_background_callback.dart \
  test/platform/background/android/android_background_callback_test.dart
2 files formatted; 0 changed

git diff --check
Passed

flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://api.example.org
[!] No Android SDK found

flutter doctor -v
Flutter 3.44.8 / Dart 3.12.2
Android toolchain: ✗ unable to locate SDK
Linux toolchain: ✓
Linux device: ✓

flutter test <four focused Android/WorkManager test files>
15 tests passed

flutter test test/features/background_sync \
  test/platform/background/workmanager test/platform/background/android
25 tests passed

dart analyze --fatal-infos \
  lib/src/platform/background/android \
  lib/src/platform/background/workmanager \
  test/platform/background/android \
  test/platform/background/workmanager
No issues found

flutter build linux --release
Built build/linux/x64/release/bundle/leb2-watch
```

The replacement-survival test was added before the callback correction and
failed to compile because `AndroidBackgroundSyncTaskHandler` still required the
unsafe `cancelPending` capability. After removing that capability and its
dispatcher wiring, all four callback tests and the 30-test grouped batch passed.

The repository-wide suite reached 766 passing tests with exactly one expected
failure in the deferred shared platform-factory test, which still asserted that
Android was unsupported. Repository-wide analysis was also attempted; only
parallel desktop-worker lints remained. Final shared-test and lint integration
belongs to the serialized Phase 13 integration pass.

The Linux build is only a host-platform compile check for shared Dart imports;
it is not evidence of Android runtime behavior.

## Known limitations

- The release APK command failed immediately with `[!] No Android SDK found`.
  `flutter doctor -v` confirmed Flutter 3.44.8/Dart 3.12.2 and an available
  Linux toolchain/device, but no Android SDK. Gradle resolution, manifest
  merging, APK compilation, emulator execution, reboot recovery, and actual
  background plugin access remain unverified. No APK was produced.
- On a host with an Android SDK, rerun exactly:

  ```text
  flutter build apk --release --dart-define=APP_ENV=production --dart-define=BACKEND_BASE_URL=https://api.example.org
  ```
- Headless-only disabled, missing-target, or paused states can leave the
  periodic chain scheduled. Those wakes remain local no-ops and perform no
  HTTP.
- True terminal headless self-cancellation needs a native-owned,
  generation-aware coordinator plus Android device validation. The current
  plugin does not expose native operation completion or a safe generation
  cancellation boundary.
- WorkManager does not expose a cooperative Dart cancellation callback when
  Android stops the worker; the execution-budget hook is the available
  cooperative bound.
- OEM battery restrictions and force-stop behavior require device validation.
- Notification delivery cannot be proven by a completed plugin future.

## Future considerations

On an Android-capable host, build debug and release APKs, inspect the merged
manifest and JobScheduler state, then exercise offline constraints, repeated
registration, permission denial, process death, reboot, force-stop/reopen,
session expiration, baseline silence, and exactly-once notification behavior.
For session expiration specifically, verify that foreground reconciliation
owns cancellation, replace the session, and confirm that the retained desired
preference causes exactly one fresh unique registration. If terminal
headless-only cancellation becomes a requirement, implement and validate the
native coordinator before changing callback ownership.

## Related contexts

- `docs/contexts/background-scheduler.md`
- `docs/contexts/assignment-synchronization.md`
- `docs/contexts/synchronization-backoff.md`
- `docs/contexts/local-notifications.md`
- `docs/contexts/new-assignment-notifications.md`
- `docs/contexts/deadline-reminders.md`
