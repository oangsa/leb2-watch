# Platform Validation — Compacted Context

## Status

Partial. Android background synchronization and WorkManager have implementation
and bounded host/static evidence, but required native runtime proof remains
incomplete; Linux 20.1-20.3 are complete, 20.4 X11/GNOME is intentionally
skipped for the current preview, and 20.5 Flatpak packaging has a built,
installed, and smoke-tested preview artifact. Host and Flatpak live API
reachability is proven; authenticated package flow and login/reboot autostart
remain unverified. Other platform records retain their stated validation
boundaries.

## Purpose

Compacted context for the platform validation feature area. Consolidated from historical records.

## Scope

The historical feature records are consolidated in the retained area sections below.

## Architecture

### Architecture

`android/app/build.gradle.kts` conditionally applies an ignored
`android/key.properties` release configuration. Flutter's `bundleRelease`
path uses that Release build type. No app source or Gradle logic changed for
this validation.

### State and control flow

1. Flutter invokes Gradle's `bundleRelease` task with sanitized Dart defines.
2. The ignored external test signing configuration signs the Release artifact.
3. The output AAB is checked as a ZIP and for bounded required/forbidden
   entries.
4. `jarsigner` verifies embedded archive signatures.
5. The strict JDK diagnostic separately exposes certificate-chain trust.

### Architecture

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

### State and control flow

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

### Architecture

`integration_test/android_local_notification_runtime_test.dart` constructs the
real plugin, production adapter, and production local-notification service.
It initializes the service, invokes `requestPermission()`, verifies the
delivery toggle, calls `showTestNotification()`, and finally cancels only
`LocalNotificationIdFactory.testNotificationId` through the adapter.

The smoke creates no Riverpod container, database, credential store, backend
client, session, or assignment. The fixed test notification has no payload.

### State and control flow

1. The caller starts a disposable API 36 emulator and installs a sanitized,
   externally test-signed Release APK for build/manifest validation.
2. The caller uses the disposable test app state and grants notification
   permission explicitly (manually for dialog observation, or `adb pm grant`
   for deterministic submission validation).
3. The opt-in integration smoke initializes the production adapter/service,
   requests permission, reads the delivery state, and submits the fixed test.
4. `finally` cancels exactly the fixed ID and disposes the service/adapter.
5. A host may query `dumpsys notification` for the known package/channel/ID.
   Only an unambiguous matching record is evidence of notification-manager
   state at that instant; an unavailable or ambiguous query is documented, not
   substituted with a visual or application-level success claim.

### Architecture

`android_local_data_deletion_runtime_test.dart` composes
`LocalDataDeletionCoordinator` with the production secure credential store,
Drift manager/storage cleanup, quiescence-aware local notification service,
Android WorkManager scheduler, cache cleanup, and unsupported mobile
autostart adapter. It seeds deterministic inert values only after the guard
passes. `deleteAll()` retains the normal deletion gate and native adapter
calls; `finally` repeats bounded cleanup if an assertion or platform call
fails.

### State and control flow

1. Guard rejects non-Android or missing opt-in before any write.
2. The test writes two inert secure-store values and one owned cache sentinel.
3. The production coordinator quiesces activity, cancels supported effects,
   clears credentials, scrubs/closes/deletes SQLite files, clears the owned
   cache, resets providers, and releases the gate.
4. The test reads only fixed postconditions, then opens/closes a fresh empty
   database.
5. `finally` independently retries only bounded app-owned cleanup calls.

### Architecture

`MainActivity` calls a variant-specific
`configureDebugWorkmanagerRuntimeInspector`. The debug implementation registers
`dev.oangsa.leb2watch.test/workmanager-runtime`; release and profile variants
compile no-op implementations. The debug channel queries only
`dev.oangsa.leb2watch.periodic-sync.v1` with public
`WorkManager.getWorkInfosForUniqueWork`, then returns active (`ENQUEUED` or
`RUNNING`) records with state, network type, periodicity, and opaque generation
tags. It never exposes WorkRequest input, credentials, backend data, paths, or
raw native errors.

`integration_test/android_workmanager_runtime_test.dart` constructs the
production `AndroidWorkmanagerSchedulerPlatform` with inert deterministic
generation tags. It cancels, schedules, re-registers, and cancels again while
polling the sanitized snapshot, with cleanup in `finally`.

### Architecture

`IosWorkmanagerSchedulerPlatform` implements the shared
`BackgroundSchedulerPlatform`. It initializes Workmanager with the retained
iOS dispatcher, schedules the exact stable identifier, cancels only that
identifier, and obtains status from
`IosBackgroundRefreshStatusBridge`. It intentionally does not call
Workmanager's unsupported iOS `isScheduledByUniqueName`.

`iosBackgroundCallbackDispatcher` is a top-level VM entrypoint.
`IosBackgroundExpirationTaskDispatcher` handles only the exact refresh task,
attaches one expiration lease, injects it as
`WorkmanagerTaskExecutionContext.cancellation`, and closes it in `finally`.
An unknown task completes without attaching. A failed or timed-out attach
returns the app's Dart `false` result before the sync handler opens its
database or performs HTTP. A lease already expired at attach skips the handler
entirely and still detaches.

For live expiration, the dispatcher races the handler's fully error-mapped
outcome against the lease. Expiration returns the Dart callback promptly even
if the handler is waiting for composition open or target-policy read. The late
handler Future remains observed and retains its own ownership. If startup
later resumes, it sees the same cancelled lease, performs no HTTP, and closes
the composition after its use ends; ownership is never closed underneath a
late read.

`IosBackgroundSyncTaskHandler` opens the Feature 13.1 owned headless
composition and runs the shared synchronization service. Its 25-second budget
applies to the runner's active synchronization race after composition open,
local policy read, and synchronization-Future construction. It is not a
whole-callback or startup deadline.

Workmanager resubmits the next BGAppRefresh request before Dart runs. The
handler therefore cancels that exact pending request when durable local policy
reports monitoring disabled, no target, or an inactive/expired session.
Success, durable backoff deferral, and no background-monitored courses leave
the next best-effort request intact. Failed/cancelled work returns Dart

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### State and control flow

1. AppDelegate registers the exact BGAppRefresh launch handler before launch
   returns.
2. The shared scheduler reads saved desired state and active-session policy.
3. Enabling initializes Workmanager and submits the same unique task with the
   saved first-delay jitter.
4. iOS decides whether and when to launch the task.
5. AppDelegate creates generation A, delegates to Workmanager, then chains
   Workmanager's installed expiration handler.
6. Workmanager resubmits the next request, creates a headless engine, and
   registers both generated plugins and the app-owned expiration bridge.
7. The exact Dart dispatcher attaches a bounded lease for A. A latched or live
   expiration completes that lease.
8. A latched expiration skips the handler. A live expiration races and can
   release the outer Dart callback while the handler's mapped Future retains
   late ownership.
9. Otherwise the handler opens fresh provider/database ownership and runs the
   shared background runner with the lease. The 25-second active-sync budget
   begins only after composition and policy startup.
10. The runner performs local gates before HTTP and reuses durable
   single-flight, backoff, cache, session-expiration, notification, and
   deadline-reminder behavior.
11. If synchronization is already active when expiration arrives, the runner
    requests `AssignmentSyncService.cancelCurrent`; the owned backend request
    cancels its Dio `CancelToken`. During earlier startup, the cancelled lease
    instead prevents any HTTP request after startup resumes.
12. Stop gates cancel only the exact resubmitted request.
13. The lease detaches in `finally`. The owned composition closes only after
    its handler use is terminal. If active synchronization cancellation does
    not settle within the shared one-second drain, its retained
    close-after-quiescence continuation keeps the database open until both the
    cancellation request and original synchronization are terminal.
14. Dart `true`/`false` controls Workmanager's fetch/debug result. For this
    pinned BGTask path, native success is `!operation.isCancelled`; only the
    actual Apple expiration chain cancels that Operation. Ordinary Dart
    failures therefore still complete the native BGTask as successful.

### Architecture

`integration_test/linux_autostart_runtime_test.dart` constructs the production
service directly with the production `launch_at_startup` adapter. The adapter
uses `HOME` and writes the fixed `LEB2 Watch.desktop` entry. The test requires
both `LEB2_WATCH_LINUX_AUTOSTART_RUNTIME_TEST=true` and Linux, then rejects a
home path outside `/tmp/leb2-watch-linux-autostart.` before any mutation.

### State and control flow

The smoke starts disabled, enables and re-reads the OS state, compares the
exact desktop-entry text, disables and re-reads state again, then removes only
the known entry in `finally`. The shell creates and removes the prefix-checked
temporary HOME outside the test process.

### Architecture

`integration_test/linux_desktop_tray_runtime_test.dart` constructs
`DesktopRuntimeCoordinator` with:

- `_TrayPlugin` — logs all tray operations and captures menu keys from
  `setContextMenu`.
- `_WindowPlugin` — logs window operations (show, focus, hide, destroy,
  preventClose).
- `_DialogClosePrompt` — always returns `keepRunning`, tracks call count.
- `_TestMonitoringSettings` — emits settings via a controllable
  `StreamController`, mutates enabled state on set.
- `_NoopBackgroundSyncTargetStore` — returns expired session policy.
- `_NoopAssignmentSyncService` — returns `SyncCancelled` for all sync calls.
- `TrayManagerDesktopTrayPlatform(operatingSystem: linux, plugin: _TrayPlugin)`
- `WindowManagerDesktopWindowPlatform(plugin: _WindowPlugin)`
- `createDesktopAutostartService()` — production service (no-op under disposable HOME).
- `DesktopBackgroundSchedulerPlatform()` — disposed after coordinator.

`integration_test/support/linux_desktop_tray_runtime_guard.dart` provides:

- `linuxDesktopTrayRuntimeTestOptIn` — compile-time bool from environment.
- `allowsLinuxDesktopTrayRuntimeTest` — requires both opt-in and Linux.
- `requireLinuxDesktopTrayRuntimeTestOptIn` — throws if conditions not met.
- `isDisposableLinuxDesktopTrayRuntimeHome` — prefix check for `/tmp/leb2-watch-linux-tray.`

`test/platform/desktop/linux_desktop_tray_runtime_guard_test.dart` verifies
the guard predicates in pure Dart without platform dependencies.

### State and control flow

1. Coordinator initializes: tray menu built with stable keys, autostart read,
   monitoring settings observed.
2. First close: prompt shown, returns keepRunning, window hidden.
3. Second close: no prompt, window hidden directly.
4. Tray open: window shown then focused (order verified by log index).
5. Tray quit: listeners removed, tray destroyed, window destroyed. Log order
   confirms teardown sequence.
6. Pause/resume: menu toggles between pause and resume monitoring keys.

### Architecture

`integration_test/linux_local_notification_runtime_test.dart` constructs a
real `FlutterLocalNotificationsPlugin`, injects it into
`FlutterLocalNotificationsAdapter`, and constructs
`LocalNotificationServiceImpl`. It does not use a fake platform. After the
service encodes and submits a synthetic `NewAssignmentNotification`, the test
asserts the live Linux delivery state is `notRequired` and reads the public
Linux plugin system-ID map. Default mode calls KDE's server-owned
`org.kde.NotificationManager.InvokeAction` for `default`; explicit manual mode
waits up to two minutes for the owner to click the visible notification. Both
paths require the service response stream to emit the exact
`AssignmentNotificationTarget`.

### State and control flow

1. Preflight verifies the target platform and live KDE action endpoint.
2. The service initializes and subscribes to responses before submission.
3. The service submits the synthetic new-assignment notification.
4. The Linux plugin returns the KDE system ID for the exact app ID.
5. Default mode invokes KDE `default`; manual mode waits for the owner to click
   the live notification.
6. The test awaits one exact decoded target.
7. `finally` cancels only the known app ID, then disposes the stream/service.

### Architecture

`PrivacyPage` uses existing design system. `AppRoute.privacy` accessible at every flow stage. `SettingsPage` pushes privacy route.

**Android signing**: `android/key.properties` ignored by VCS. Build reads it; if absent, artifact marked unsigned/non-distributable. If present but incomplete, redacted failure.

**Test orchestration**: `flutter_test_runner.dart` discovers all `test/**/*_test.dart`, partitions into batches of ≤10, executes sequentially in fresh processes with `--concurrency=1`, fail-fast on first failure.

**AAB validation**: External test-signed Release AAB passed ZIP integrity and non-strict JAR signature (`jarsigner -verify` exit 0). Strict check (`jarsigner -verify -strict -certs`) returned exit 4 (self-signed signer not in default JDK trust store) — not a trusted chain verification.

### Architecture

`DesktopWindowRevealSignal` is a Riverpod-owned broadcast signal carrying no
payload. `Leb2WatchApp` requests it synchronously before calling the named
assignment-detail route. `DesktopRuntimeHost` subscribes during `initState`,
before its asynchronous coordinator composition. If a response arrives early,
the host retains one pending reveal until initialization completes.

`DesktopRuntimeCoordinator.openWindow()` owns the shared show-then-focus
operation used by both the tray Open action and notification reveal. Show
failure ends the attempt; focus failure is bounded and non-fatal.

The unpackaged preview composes
`DesktopDeadlineReminderDeliveryCoordinator`. It consumes versioned future
events from local SQLite and uses the supported immediate-notification path
when a threshold becomes due. It does not report Windows OS scheduling or
cancellation as supported.

The native runner sets `SetQuitOnClose(true)`. The pre-run hook initializes
`window_manager` without enabling close prevention. Runtime composition
attaches the Dart close listener before enabling prevention. Healthy
interception still owns close-to-tray, while a destroyed fallback window posts
the native quit message.

### State and control flow

1. Pre-run startup initializes the window plugin while conventional close
   remains enabled.
2. Runtime composition attaches the close listener, then enables close
   prevention.
3. The app creates the router, reveal signal, and notification coordinator.
4. The desktop host subscribes to reveal requests before asynchronous desktop
   composition.
5. A validated response waits until `AppFlowStage.ready`.
6. The app requests reveal synchronously.
7. If the coordinator is ready, the host calls show then focus. Otherwise one
   pending reveal is retained until it becomes ready.
8. The app requests the assignment-detail named route after the reveal request.
9. Host disposal detaches the reveal subscription and clears any pending
   request.
10. Fresh unpackaged-Windows deadline events use the separate process driver.
    Explicit Quit disposes that driver before native window destruction.

## Important Files

### Important files

- `android/app/build.gradle.kts` — existing conditional Release signing
  contract.
- `android/.gitignore` — excludes local signing properties and keystore files.
- `test/platform/android/android_release_signing_configuration_test.dart` —
  guards the no-debug-fallback and signing-redaction policy.
- `docs/configuration-and-builds.md` — operator build instructions and AAB
  boundary.
- [This compact's validation evidence](#validation-evidence) — cross-platform
  validation evidence.

### Important files

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
- `android/app/src/debug/kotlin/dev/oangsa/leb2watch/DebugWorkmanagerRuntimeInspector.kt`
  — debug-only, fixed-name public WorkManager snapshot used solely by the
  guarded integration test; release/profile variants are no-ops.
- `test/platform/background/android/` — Android scheduling, callback, and
  manifest coverage.
- `test/platform/android/android_release_signing_configuration_test.dart` —
  release-signing and narrow Room shrinker-rule regression coverage.
- `test/platform/background/workmanager/` — shared dispatcher coverage.

### Important files

- `integration_test/android_local_notification_runtime_test.dart` — opt-in
  production-adapter/service smoke and exact-ID cleanup.
- `lib/src/features/notifications/data/flutter_local_notifications_adapter.dart`
  — Android plugin initialization, permission, status, show, and cancel calls.
- `lib/src/features/notifications/application/local_notification_service_impl.dart`
  — production initialization, permission mapping, and fixed test submission.
- `lib/src/features/notifications/domain/local_notification_id_factory.dart`
  — reserved fixed test notification ID.
- `android/app/src/main/AndroidManifest.xml` — app scheduling receiver policy;
  merged Release output is the authority for plugin-provided notification
  permission declarations.

### Important files

- `integration_test/android_local_data_deletion_runtime_test.dart` — guarded
  emulator smoke and bounded cleanup.
- `integration_test/support/android_native_local_data_deletion_guard.dart` —
  compile-time Android/opt-in gate.
- `test/platform/android/android_native_local_data_deletion_guard_test.dart` —
  guard truth-table coverage.
- `lib/src/features/settings/data_deletion/data/local_data_cleanup_adapters.dart`
  — production adapters under test.

### Important files

- `android/app/src/debug/kotlin/dev/oangsa/leb2watch/DebugWorkmanagerRuntimeInspector.kt` — debug-only public-API native inspector.
- `android/app/src/release/kotlin/dev/oangsa/leb2watch/DebugWorkmanagerRuntimeInspector.kt` — release no-op.
- `android/app/src/profile/kotlin/dev/oangsa/leb2watch/DebugWorkmanagerRuntimeInspector.kt` — profile no-op.
- `integration_test/android_workmanager_runtime_test.dart` — guarded native-runtime scenario.
- `integration_test/support/android_workmanager_runtime_guard.dart` — Android/opt-in gate.
- `test/platform/android/android_workmanager_runtime_native_configuration_test.dart` — source boundary checks.

### Important files

- `lib/src/platform/background/ios/ios_background_contract.dart` — exact task
  identity and 25-second active-synchronization budget.
- `lib/src/platform/background/ios/ios_background_callback.dart` — retained
  exact-task expiration-aware dispatcher and result policy.
- `lib/src/platform/background/ios/ios_background_expiration_bridge.dart` —
  typed, bounded Dart bridge and cancellation lease.
- `lib/src/platform/background/ios/ios_workmanager_scheduler_platform.dart` —
  shared scheduler adapter.
- `lib/src/platform/background/ios/ios_background_refresh_status_bridge.dart`
  — typed MethodChannel boundary.
- `lib/src/platform/background/families/ios_background_scheduler_factory.dart`
  — iOS family wiring.
- `ios/Runner/AppDelegate.swift` — app-owned launch registration, Workmanager
  delegation, native generation coordinator, expiration chain, headless
  expiration bridge, and foreground status bridge.
- `ios/Runner/Info.plist` — permitted identifier and `fetch` mode.
- `ios/Runner.xcodeproj/project.pbxproj` — iOS 14 deployment floor.
- `ios/RunnerTests/RunnerTests.swift` — native availability mapping test.
- `test/platform/background/ios_background_*_test.dart` — Dart and static
  host validation.

### Important files

- `integration_test/linux_autostart_runtime_test.dart` — guarded production
  enable/disable smoke.
- `integration_test/support/linux_autostart_runtime_guard.dart` — opt-in,
  platform, and disposable-home predicates.
- `test/platform/desktop/linux_autostart_runtime_guard_test.dart` — pure guard
  coverage.
- `lib/src/platform/desktop/autostart/desktop_autostart_service.dart` —
  production service under test.
- `lib/src/platform/desktop/autostart/flatpak_desktop_autostart_platform.dart`
  — sandbox-aware XDG autostart adapter.
- `lib/src/platform/desktop/autostart/launch_at_startup_desktop_autostart_platform.dart`
  — production plugin adapter under test.

### Important files

- `packaging/flatpak/dev.oangsa.leb2watch.json` — selected Flatpak preview
  manifest and sandbox permissions.
- `packaging/flatpak/metadata/` — desktop entry and AppStream metadata.
- `packaging/flatpak/modules/` — vendored AppIndicator compatibility recipes.
- `packaging/flatpak/README.md` — build, bundle, and validation boundary.

### Important files

- `integration_test/linux_local_notification_runtime_test.dart` — opt-in KDE
  submission/action smoke and exact-ID cleanup.
- `lib/src/features/notifications/data/flutter_local_notifications_adapter.dart`
  — production plugin boundary used by the smoke.
- `lib/src/features/notifications/application/local_notification_service_impl.dart`
  — production payload validation and response publication used by the smoke.
- [Notifications compact](../notifications/COMPACT.md#architecture) —
  service-wide capability and limit record.

### Important files

- `lib/src/features/privacy/privacy_page.dart` — privacy disclosures page
- `lib/src/features/settings/settings_page.dart` — privacy route push action
- `lib/src/core/testing/flutter_test_runner.dart` — test discovery, partitioning, sequential execution
- `android/app/build.gradle.kts` — signing configuration
- `test/flutter_test_runner_test.dart` — orchestration unit tests

### Important files

- `windows/runner/main.cpp` — per-session mutex, second-instance activation,
  and native quit-on-destroy fallback.
- `lib/src/platform/desktop/runtime/desktop_window_reveal_signal.dart` —
  payload-free process-local signal.
- `lib/src/platform/desktop/runtime/desktop_runtime_host.dart` — reveal
  subscription, early-request retention, and disposal.
- `lib/src/platform/desktop/runtime/desktop_runtime_coordinator.dart` —
  reusable show/focus operation and guarded desktop lifecycle.
- `lib/src/platform/desktop/desktop_pre_run_app_hook.dart` — non-intercepting
  plugin initialization before `runApp`.
- `lib/src/platform/desktop/window/window_manager_desktop_window_platform.dart`
  — listener-before-prevention ordering and failed-initialization rollback.
- `lib/src/app/app_dependencies.dart` — signal ownership.
- `lib/src/app/leb2_watch_app.dart` — reveal-before-route ordering.
- `lib/src/features/notifications/data/local_notifications_platform.dart` —
  packaged/unpackaged capability matrix.
- `lib/src/features/notifications/application/desktop_deadline_reminder_delivery_coordinator.dart`
  — process-lifetime due-event timer and delivery.
- `.github/workflows/ci.yml` — Windows Release build job with sanitized
  compile-time definitions.
- `test/platform/desktop/` — native, coordinator, reveal-subscription, and
  disposal coverage.
- `test/app/leb2_watch_app_notifications_test.dart` — reveal-before-route
  integration coverage.
- `test/features/notifications/data/flutter_local_notifications_adapter_test.dart`
  — packaged/unpackaged capability coverage.

## Contracts and Interfaces

### Contracts and interfaces

The operator build command is:

```text
flutter build appbundle --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid
```

The output inspected was:

```text
build/app/outputs/bundle/release/app-release.aab
SHA-256: e5e1d775cd6437cb9d4bb24ebc2e49ccfb5c463f0752a9811857e9edcf32b084
```

The placeholder origin is intentionally invalid and proves no backend request.
For a real operator release, replace it only at rebuild time with that
operator's self-hosted HTTPS origin.

### Contracts and interfaces

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

### Contracts and interfaces

The smoke requires `TargetPlatform.android` and a caller-granted
`POST_NOTIFICATIONS` permission. It intentionally calls the production
permission-request API rather than relying solely on `adb pm grant`; granting
permission beforehand makes this noninteractive check deterministic but does
not prove that a system dialog was rendered or understood.

`showTestNotification()` uses only the application-owned fixed test ID and
fixed local copy. A completing Future proves plugin submission, not visible
rendering, alerting, persistence, accessibility, or user delivery.

### Contracts and interfaces

The integration test requires both:

```text
target platform: Android
LEB2_WATCH_DESTRUCTIVE_LOCAL_DATA_TEST=true
```

It does not send a request or import a backend client. The run uses the
non-routable documentation origin `https://backend.example.invalid` only to
satisfy app configuration; no source reads or calls it.

### Contracts and interfaces

The inspector accepts only a no-argument `snapshot` call and is hard-wired to
the production unique name. AndroidX WorkManager 2.10.2 exposes the public
`WorkInfo.constraints.requiredNetworkType` and `WorkInfo.periodicityInfo`
members used for metadata assertions. No reflection, private database query, or
`adb dumpsys` parsing is used.

### Contracts and interfaces

The identifier is identical for native registration, Workmanager unique name,
Workmanager task name, pending-request lookup, cancellation, and dispatcher
lookup:

```text
dev.oangsa.leb2watch.assignment-refresh
```

The separate headless expiration channel is:

```text
dev.oangsa.leb2watch/background_refresh_expiration
attach -> { generation: <lowercase UUID>, expired: <bool> }
expired({ generation: <lowercase UUID> })
detach({ generation: <lowercase UUID> })
```

The adapter requests the shared 15-minute cadence and persisted first-submit
jitter. On iOS the Dart `frequency` does not control native recurrence.
AppDelegate passes 15 minutes to Workmanager's native BGAppRefresh
registration; Workmanager uses it only as the earliest-begin interval when
resubmitting. Actual timing is system controlled.

Status maps as follows:


*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Contracts and interfaces

The smoke uses `DesktopAutostartService.initialize`, `watch`, and `setEnabled`.
It requires `DesktopAutostartUpdateApplied` and an available snapshot after
each successful operation. The tested Linux entry is exactly
`$HOME/.config/autostart/LEB2 Watch.desktop`.

### Contracts and interfaces

- `DesktopRuntimeCoordinator.initialize()` — builds tray menu, reads autostart
  state, watches monitoring settings.
- `DesktopRuntimeCoordinator.handleCloseRequest()` — shows explanation on first
  call, hides directly on subsequent calls.
- `DesktopRuntimeCoordinator.handleTrayAction(key)` — dispatches by stable action
  key; open shows+focuses, quit tears down.
- `DesktopRuntimeCoordinator.quit()` — removes listeners, destroys tray, permits
  close, destroys window. Completes without hanging.

### Contracts and interfaces

The test requires `TargetPlatform.linux`, `gdbus`, a freedesktop notification
server identifying as KDE Plasma, the `actions` capability, and KDE's
`InvokeAction` endpoint. It uses `LinuxFlutterLocalNotificationsPlugin`
`getSystemIdMap()` only to find its own app notification ID. Compile-time
`LEB2_WATCH_LINUX_NOTIFICATION_MANUAL_TAP=true` selects the bounded human-tap
path; the default remains deterministic and automatic.

### Contracts and interfaces

`DesktopWindowRevealSignal.requestReveal()` emits one synchronous, payload-free
process-local request while the signal is open. `dispose()` closes the stream.

`DesktopRuntimeCoordinator.openWindow()`:

1. returns without platform work after coordinator disposal;
2. awaits `show()`;
3. returns if show fails; and
4. requests `focus()` but treats focus denial as non-fatal.

Windows capabilities are:

| Artifact | Immediate | Scheduling | Cancellation | Launch payload |
| --- | --- | --- | --- | --- |
| Current unpackaged preview | yes | no | no | no |
| Future package-identity capability | yes | yes | yes | yes |

The second row is a capability representation only. This repository does not
implement or claim a packaged Windows artifact.

The current artifact's **Scheduling** value remains `no`: process-lifetime
delivery is an application timer followed by immediate show, not an
OS-retained future schedule.

## Decisions

### Decisions

- Use `unzip -t` for container integrity and `jarsigner -verify` for the
  signed ZIP/JAR archive result.
- Preserve `jarsigner -verify -strict -certs` as a diagnostic rather than
  hiding its nonzero result.
- Do not use `apksigner`, which verifies APKs rather than AABs.
- Do not repurpose Gradle's non-runnable cached Bundletool module as the
  standalone Bundletool CLI.

### Decisions

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Decisions

- Reuse the existing fixed test notification instead of adding a synthetic
  assignment payload or changing product code.
- Require pre-granted permission so the command is deterministic and cannot
  falsely report automated system-dialog evidence.
- Keep system-notification-manager inspection an optional bounded evidence
  step because API/image output may not expose a safely identifiable record.

### Decisions

- Use a compile-time opt-in rather than an environment/runtime switch so the
  destructive operation cannot run in ordinary host tests.
- Reuse production ports rather than create test-only deletion behavior.
- Treat plugin Future success as invocation evidence only.

### Decisions

- Use `BGAppRefreshTask`, not `BGProcessingTask`, for a short content refresh.
- Use stock Workmanager rather than a custom native engine.
- Register one stable reverse-DNS identifier and cancel only that identifier.
- Query native pending requests because Workmanager's public iOS scheduled
  query is unsupported and its submit method does not surface native errors.
- Keep exact next execution null on iOS.
- Delegate through Workmanager's public native handler rather than duplicating
  its scheduling, engine, Operation, and completion machinery.
- Bind one opaque generation to each delivered native task so an old
  expiration or detach cannot affect a later invocation.
- Fail closed before sync when the headless bridge cannot attach.
- Keep a conservative 25-second active-synchronization budget as secondary
  protection; do not present it as a startup or whole-callback bound.
- Preserve Feature 13.1 foreground lifecycle fallbacks.

### Decisions

- Use a compile-time opt-in and runtime Linux guard to fail closed.
- Test the production adapter rather than a fake so the dependency's actual
  `HOME`-based entry management is exercised.
- Assert the exact entry content rather than treating file presence as enough
  evidence.

### Decisions

- Use injected platform adapters rather than a full Linux device run, keeping
  the test fast and deterministic while exercising the same coordinator logic.
- Require compile-time opt-in to prevent accidental execution in CI or on
  non-Linux platforms.
- Use a controllable `StreamController` for monitoring settings so tests can
  verify reactive menu rebuilds without a database.
- Include a pure unit test for the guard predicates to verify logic without
  platform dependencies.

### Decisions

- Keep cleanup at the existing adapter `cancel(id)` seam instead of adding a
  broad product API solely for a test.
- Use a fixed valid ID outside the reserved test ID so cleanup is exact and
  auditable.
- Keep automated KDE server acceptance/action evidence distinct from the
  explicit manual mode that proves one visible human-click path.

### Decisions

- Keep healthy plugin close interception as the owner of close-to-tray while
  making native destroy the safe exit fallback.
- Keep pre-run initialization non-intercepting and attach the close listener
  before enabling prevention so startup failure cannot strand an uncloseable
  window.
- Reuse one coordinator show/focus operation for tray and notifications.
- Send a payload-free signal rather than exposing a window plugin to app or
  notification layers.
- Retain at most one early reveal because visibility requests are idempotent
  and no business event belongs in this seam.
- Keep package-identity capability represented for future work while reporting
  the current unpackaged artifact truthfully.
- Build the complete Release directory in CI without publishing or presenting
  it as an installer.

## Known Limitations

### Known limitations

- No standalone Bundletool validation is available locally.
- No trusted certificate-chain result exists for the external test signer.
- No APK set was generated or installed from this AAB.
- No runtime, Play acceptance, Play App Signing, store, production signer, or
  physical-device conclusion follows from this artifact validation.

### Known limitations

- A verified sanitized backend fixture, session, semester, and course have not
  been supplied. Therefore this validation does not prove native unique-work
  registration/execution, network constraints, baseline/diff notification
  behavior, session expiry/recovery, visible notification delivery, reminder
  rescheduling, secure-storage CRUD, durable cancellation, or end-to-end
  delete-all behavior.
- No notification permission was granted and no test notification was sent.
  The absence of a prompt during onboarding is proven; the OS permission state
  and delivery path are not.
- The AVD is an emulator-only result. USB device validation remains unrun; the
  host does not have the optional `android-udev` package installed.
- Reboot and force-stop recovery of a scheduled worker are untested. The
  observed force-stop/relaunch proves foreground startup only.

- A prior no-SDK host result is superseded by the 2026-07-27 Release build and

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Known limitations

The integration test cannot prove that Android displayed a permission dialog,
showed pixels, alerted the user, retained the notification, received a tap,
or cold-launched the app. A test notification manager record, if safely
observable, is limited to OS state at one observation time. It is not a
delivery receipt.

The integration test is intentionally excluded from the host-only serial
runner and remains a separate device command.

### Known limitations

- The smoke does not prove Android visibly removed notifications.
- It does not prove WorkManager cancellation is durable, stops active work, or
  survives reboot/force-stop.
- Direct secure-store reads are not forensic Android Keystore erasure proof.
- No physical device, OEM policy, backend/session, or user-flow navigation was
  exercised.

### Known limitations

The guarded API 36 integration test proves one observed native registration,
replacement, connected-network constraint value, and empty active-record
snapshot after cancellation. It does not prove worker execution,
connected-network blocking, cancellation durability, reboot/force-stop
recovery, or physical-device behavior.

### Known limitations

- iOS build, Swift type checking, signing, BGTask execution, Keychain access,
  Drift headless access, notifications, and forced expiration are unverified.
- The pinned Workmanager 0.9.0+3 / workmanager_apple 0.9.1+2 implementation
  installs its handler synchronously. Every dependency upgrade must re-audit
  the public method signature, handler timing/readability, headless registrant
  order, and native completion behavior.
- A very small takeover interval exists between Workmanager installing its
  handler and AppDelegate replacing it with the chain. An expiration in that
  interval would invoke Workmanager cancellation but not the Dart bridge. A
  plugin/upstream hook is required to remove this interval completely.
- The generation coordinator assumes iOS does not concurrently deliver two
  executions of this same BGAppRefresh identifier. Same-identifier stale
  callbacks are fenced, but truly overlapping engines would require task
  metadata from Workmanager.
- If cancellation fails to quiesce in the existing one-second drain,

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Known limitations

This does not prove that a desktop session launches the executable, that a
user sees a desktop environment integration, or behavior in X11, GNOME,
Flatpak, Snap, Windows, or macOS.

### Known limitations

- Tests use injected platform adapters; they do not call native method channels.
- Live visible-shell evidence covers only the current KDE Plasma/Wayland
  session; it does not generalize to other desktops or display servers.
- X11 and GNOME runtime behavior remain intentionally unverified (skipped on
  2026-08-01).
- A production-origin Flatpak build and deeper authenticated app-flow/runtime
  validation remain unverified. The fresh localhost package is development-only
  and must not ship; autostart login/reboot launch also remains unverified.

### Known limitations

Current KDE/Wayland evidence proves one visible notification and one human
same-process click. It does not prove that a cold or terminated process can
receive an action, that deadline schedules survive process exit, or that other
Linux desktops behave the same way.

### Known limitations

- Android Release compilation proven on Linux host only. Unsigned artifact verified as unsigned.
- No verified backend fixture — no WorkManager execution, notification delivery, session expiry evidence.
- Deletion smoke proves only bounded local secure-store/SQLite/cache and cancellation.
- AVD result doesn't replace USB-device, reboot, or force-stop validation.
- AAB self-signed signer not trusted by default JDK. Bundletool, generated APK, Play acceptance unproven.
- iOS/macOS/Windows require native hosts.
- Shards bounded by file count, not duration — individual shard runtimes vary.
- Windows `flutter.bat` selection, `runInShell`, working-directory source-reviewed but not executed.

### Known limitations

- A GitHub Actions job being configured does not prove it has passed; inspect a
  resulting workflow run after commit/push.
- Windows show/focus, fallback close, mutex activation, DPAPI storage,
  autostart, tray behavior, and notifications still need live Windows 10 and
  Windows 11 tests.
- Cold/terminated notification activation is unsupported.
- OS-retained scheduled deadline reminders and reliable cancellation are
  unsupported. Process-lifetime immediate delivery is best effort and requires
  the application to remain alive.
- One instance is enforced only within one interactive session. Multiple
  sessions sharing one user's roaming application data are unsupported.
- No MSIX, installer, signing, update, store, or Visual C++ redistribution
  validation exists.

## Validation Evidence

### Tests

`test/platform/android/android_release_signing_configuration_test.dart`
continues to cover the existing local signing contract, ignored signing files,
redacted failure behavior, no debug signing fallback, and narrow Room/R8 rule.
No app code or executable signing contract changed, so no new test was added.

### Validation evidence

- `flutter build appbundle --release` with sanitized production defines:
  passed; output was `app-release.aab` (63.9 MB).
- `sha256sum`: recorded the SHA-256 above.
- `unzip -t`: exit `0`, no compressed-data errors.
- Bounded archive inventory: required `BundleConfig.pb`, base manifest, and
  two DEX files present; forbidden signing/configuration entries absent.
- `jarsigner -verify`: exit `0`, `jar verified.` The non-strict command still
  reported its self-signed/untrusted chain, missing timestamp, POSIX-attribute,
  and JarFile/JarInputStream consistency warnings.
- `jarsigner -verify -strict -certs`: exit `4`, self-signed/untrusted-chain
  diagnostic; not a strict-trust pass.
- The full 1,097-test/14-shard host-suite result predates this documentation-
  only feature change and is historical rather than fresh AAB-feature test
  evidence. Focused tests and no-write checks are recorded with this feature.

### Tests

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

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

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

- `integration_test/android_local_notification_runtime_test.dart` — production
  Android initialization, explicit permission request/readback, fixed test
  submission, and exact-ID cleanup.

### Validation evidence

Run only in the authorized disposable Android environment, after sourcing
`~/.zshrc` once in the terminal before its first Flutter/Dart command:

```bash
# Build/inspect the sanitized external-test-key Release before device use.
flutter build apk --release \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid

# Install the resulting Release for independent startup/build validation.
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Start the smoke. Flutter installs its debug test app itself, so do not grant
# permission before this command has installed it.
flutter test integration_test/android_local_notification_runtime_test.dart \

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

- Guard truth table: focused host test passed.
- Guarded integration smoke: one Android API 36 emulator test passed.

### Validation evidence

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

### Tests

- `android_workmanager_runtime_guard_test.dart` verifies the opt-in truth table.
- `android_workmanager_runtime_native_configuration_test.dart` verifies fixed
  name scoping, public metadata access, and absent release channel source.
- `android_workmanager_runtime_test.dart` verifies native registration,
  generation replacement, connected-network metadata, and cancellation on a
  disposable API 36 emulator.

### Validation evidence

Passed:

```text
flutter test test/platform/android/android_workmanager_runtime_guard_test.dart \
  test/platform/android/android_workmanager_runtime_native_configuration_test.dart
flutter analyze --fatal-infos --fatal-warnings
./gradlew :app:compileDebugKotlin --console=plain
```

The first `compileDebugKotlin` exposed an invalid `FlutterEngine` context
assumption; the inspector now receives `MainActivity.applicationContext` and a
second compile passed.

Fresh runtime evidence on 2026-07-30:

```text
flutter test -d emulator-5554 integration_test/android_workmanager_runtime_test.dart \
  --dart-define=LEB2_WATCH_ANDROID_WORKMANAGER_RUNTIME_TEST=true \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid
1 passed on API 36

flutter test test/platform/android/android_workmanager_runtime_guard_test.dart \
  test/platform/android/android_workmanager_runtime_native_configuration_test.dart
2 passed
```

The first integration invocation failed before the test body with `getVersion:
(112) Service has disappeared`; ADB briefly reported the emulator offline. The
same emulator recovered without restart, and the identical rerun passed. No
source change was required. The disposable emulator then stopped cleanly and
`adb devices -l` returned no attached devices.

### Tests

Host-runnable tests cover:

- exact Info.plist identifier and `fetch`-only mode;
- app-owned launch registration, public Workmanager delegation, original
  handler chaining, the audited Workmanager/native package pins, and separated
  foreground/headless registrants;
- all Runner deployment targets at iOS 14.0 and unchanged bundle ID;
- MethodChannel available/denied/restricted/malformed responses;
- expiration attach, pre-attach latch, live and duplicate events,
  attach-reply race buffering, malformed/stale generation rejection, exact
  detach, attach/detach failure, timeout bounds, and redaction;
- joined Workmanager initialization;
- stable scheduling identity, first delay, no iOS network constraint, and
  update policy;
- exact cancellation and native pending status without Workmanager's

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Validation evidence

On Linux:

- the focused bridge/callback/static suite plus the existing shared
  runner/composition/service/Dio cancellation chain passed 102/102 tests;
- strict owned-path Dart analysis and repository-wide Flutter analysis passed
  with no issues;
- the repository suite passed 1,081/1,081 tests across 15 serialized,
  memory-safe shards;
- code generation completed and left no generated file changed;
- repository formatting checked 327 Dart files with zero changes;
- a sanitized production Linux release build produced
  `build/linux/x64/release/bundle/leb2-watch`;
- `git diff --check` and every changed Markdown relative-link target passed;
- the changed-file high-confidence secret scan found no match, and the
  expiration channel owns only a UUID plus a boolean.

The Swift tests are source/static evidence only on Linux. The iOS build,
`RunnerTests`, and device expiration test were not run because this host has
no Xcode or physical iOS device.

### Required macOS and device validation

Run from the repository root:

```bash
source ~/.zshrc
flutter --version
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format --set-exit-if-changed .
flutter analyze
flutter test
plutil -lint ios/Runner/Info.plist
plutil -lint ios/Runner/DebugProfile.entitlements
plutil -lint ios/Runner/Release.entitlements
flutter build ios --debug --simulator
flutter build ios --release --no-codesign

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

### Tests

- `linux_autostart_runtime_guard_test.dart` covers opt-in/platform and home
  predicates.
- `linux_autostart_runtime_test.dart` covers initial disabled state,
  enable/readback, exact content, disable/readback, entry absence, and cleanup.

### Validation evidence

```text
flutter test test/platform/desktop/linux_autostart_runtime_guard_test.dart \
  test/platform/desktop/desktop_autostart_service_test.dart
6 passed

HOME=<prefix-checked disposable directory> flutter test -d linux \
  integration_test/linux_autostart_runtime_test.dart \
  --dart-define=LEB2_WATCH_LINUX_AUTOSTART_RUNTIME_TEST=true
1 passed
```

The integration invocation also checked that the exact entry was absent before
the shell removed its temporary root.

### Tests

- `linux_desktop_tray_runtime_guard_test.dart` — 2 tests: opt-in/platform
  predicates and disposable-home prefix check.
- `linux_desktop_tray_runtime_test.dart` — 3 integration tests:
  - Coordinator init/menu/close/quit lifecycle (11 assertions).
  - Pause/resume monitoring menu rebuild (3 assertions).
  - Window show-before-focus order through tray open (4 assertions).

### Validation evidence

```text
flutter test test/platform/desktop/linux_desktop_tray_runtime_guard_test.dart
2 passed

flutter test integration_test/linux_desktop_tray_runtime_test.dart -d linux \
  --dart-define=LEB2_WATCH_LINUX_DESKTOP_TRAY_RUNTIME_TEST=true
3 passed

dart analyze --fatal-infos --fatal-warnings
No issues found!

dart format --output=none --set-exit-if-changed .
348 files, 0 changed, exit 0
```

Phase 20.1 live evidence on the current KDE Plasma/Wayland session:

```text
flutter build linux --release \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://localhost:5015
PASS: exit 0; Release bundle contained the requested localhost origin

Owner visual confirmation
PASS: first frame, visible tray icon, first-close explanation,
      Keep-running hide, and tray Open/focus

App-specific accessibility and D-Bus checks
PASS: onscreen LEB2 Watch frame; one active KDE StatusNotifier item using the
      bundled Linux icon; process and tray remained after hide; exact visible
      Open action restored the frame active; exact Quit terminated the process

Isolation and cleanup
PASS: normal app-support, autostart, and runtime metadata unchanged;
      prefix-checked disposable HOME/XDG/TMP state removed
```

No credential, notification, autostart, or backend mutation was part of this
smoke. X11, GNOME, Secret Service, notification delivery/tap, deadline and
session transitions, delete-all, login launch, and packaging remain unverified.
One mis-targeted active-window screenshot was immediately deleted and excluded
from evidence; no screenshot was retained.

Phase 20.2 live evidence on the current KDE Plasma/Wayland session:

```text
Secret Service preflight
PASS: org.freedesktop.secrets owned; exact isolated attribute set absent

secret-tool create/read/update/delete
PASS: live libsecret CRUD; exact isolated entry absent after cleanup

flutter test integration_test/linux_local_notification_runtime_test.dart \
  -d linux --reporter=expanded \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://localhost:5015 \
  --dart-define=LEB2_WATCH_LINUX_NOTIFICATION_MANUAL_TAP=true
PASS: Linux delivery state notRequired; owner clicked visible notification;
      exact target decoded; 1 passed in 2 seconds; exact ID cancelled

Isolation and cleanup
PASS: successful run used disposable HOME/XDG/TMP including XDG_RUNTIME_DIR;
      normal app-support, autostart, and runtime metadata hashes unchanged;
      disposable state removed

Repository validation
PASS: format checked 351 files with 0 changes; Dart and Flutter analyzers found
      no issues; memory-safe runner passed 139 files in 14/14 shards, exit 0
```

Two earlier manual windows timed out and performed exact-ID cleanup. They used
the normal `XDG_RUNTIME_DIR`, which rewrote the app-owned
`notification_plugin_cache.json` to `{}` and changed its metadata. No normal
credential, autostart entry, backend, or system notification history was
otherwise changed. Live Secret Service evidence used the native libsecret CLI;
it does not prove the Flutter secure-storage adapter end to end.

### Tests

- Native KDE smoke: production submission, server-ID mapping, default action,
  Linux delivery-state reporting, optional bounded human tap, strict target
  decoding, and exact-ID cleanup.
- Existing notification service/adapter/native-configuration tests remain the
  focused regression coverage for application behavior and platform policy.

### Validation evidence

After sourcing `~/.zshrc` before the terminal's first Flutter command:

```text
flutter test integration_test/linux_local_notification_runtime_test.dart \
  -d linux --reporter=expanded
Built build/linux/x64/debug/bundle/leb2-watch
1 passed
```

The successful test is runtime evidence that the production path reached the
current KDE server and received its same-process `default` action callback.

### Phase 20.3 runtime state transitions — complete — 2026-08-01

Phase 20.3 passed on the current KDE/Wayland session under the approved
disposable boundary and development-only `http://localhost:5015`. The completed
run used a temporary Linux build with a unique application/keyring namespace
and isolated `HOME`, XDG, `TMPDIR`, and runtime paths. The normal release
artifact and backend repository were untouched; no credentials, cookies, user
IDs, assignment titles, or backend payloads were recorded.

```text
Focused repository proof
PASS: 81 tests across desktop deadline delivery coordinator/store/planning,
      session-expiration, deletion coordinator/adapters/quiescence, and app
      notification lifecycle seams

flutter test integration_test/end_to_end_mocked_workflow_test.dart -d linux \
  --reporter=expanded \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://localhost:5015
PASS: 2/2; sanitized session-expiration cache retention and delete-all cleanup
      completed through the hermetic production application graph

flutter build linux --release \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://localhost:5015
PASS: Release bundle built and contained the requested localhost origin;
      no missing dynamic libraries were reported
```

The host-boundary API check returned HTTP 200 for `/swagger/index.html`. A
user-interactive disposable development/test login returned sanitized 200
results for `userLogin`, `sessionCookieAcquisition`, `sessionVerification`,
`semesters`, and `semesterSnapshot`.

One cached activity in the disposable database was changed to a sanitized
course/title and future deadline. With the real Linux process alive, the
one-hour reminder was reconciled and delivered through the production
process-lifetime coordinator: the pending outbox was removed and exactly one
`deadline-submitted` history row remained, with zero deadline failure rows.
This does not prove OS-retained scheduling or process relaunch.

Delete all local data returned the app to onboarding. The reopened disposable
database had zero cached assignment, reminder, outbox, notification-history,
sync, and app-setting rows; the owned cache was empty; and the isolated
secure-storage payload was exactly `{}`. The app was then stopped and the exact
temporary profiles, build copy, and screenshots were removed.

The session-expiration/cache-retention transition remains hermetic
production-graph evidence from the 2/2 workflow; it is not live HTTP 401
evidence. A preliminary filesystem-only launch exposed the normal Secret
Service namespace, so it was stopped immediately and excluded from evidence.
The completed run used the unique namespace above.

### Phase 20.4 decision — owner-skipped — 2026-08-01

On 2026-08-01 the owner decided to skip X11 and GNOME validation for the
current Linux preview. No X11/GNOME pass claim is made; this is an intentional
scope decision, not a runtime result.

### Phase 20.5 decision — Flatpak selected — 2026-08-01

The owner selected Flatpak packaging for the Linux preview. The manifest at
`packaging/flatpak/dev.oangsa.leb2watch.json` consumes the complete Linux
release bundle, installs desktop metadata and the tray icon, and includes
vendored official AppIndicator compatibility module recipes for the sandboxed
tray integration. The current host has Flatpak 1.18.0,
`flatpak-builder` 1.4.10, and the 25.08 SDK/runtime. The earlier preview was
built, user-installed, inspected, checked in-sandbox for files/linker paths,
and launched for 20 seconds on Wayland using the development-configured
`http://localhost:5015` bundle. On 2026-08-01 a fresh current-source Release
bundle was rebuilt with `APP_ENV=development` and that localhost origin using
Flutter 3.44.8 from a disposable writable SDK copy. The manifest was rebuilt,
exported, and user-installed; metadata, permissions, and a read-only
in-sandbox file/linker/symlink smoke passed. A fresh bounded Wayland launch of
the updated package stayed alive for 20 seconds and exited 124 from the
expected timeout, with only cursor-theme and AppIndicator deprecation
warnings. A host-side Swagger preflight and the same request from the installed
Flatpak sandbox both returned HTTP 200. An unauthenticated `/Semester` request
returned HTTP 401 from both namespaces, confirming the expected auth boundary.
The exact packaged Flatpak launch command used by the generated autostart entry
stayed alive for 15 seconds and exited 124 from the bounded timeout. No
authenticated app flow or real login/reboot launch was run. This is
development-only packaging/runtime evidence; production requires an operator
HTTPS origin. Flathub publication is outside this phase.

### Validation evidence

```text
dart format --output=none --set-exit-if-changed .
dart analyze
flutter analyze
flutter build linux --release \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://localhost:5015
desktop-file-validate packaging/flatpak/metadata/dev.oangsa.leb2watch.desktop
appstreamcli validate --no-net packaging/flatpak/metadata/dev.oangsa.leb2watch.metainfo.xml
flatpak-builder --force-clean --repo=build/flatpak-repo build/flatpak \
  packaging/flatpak/dev.oangsa.leb2watch.json
flatpak build-bundle build/flatpak-repo build/leb2-watch.flatpak \
  dev.oangsa.leb2watch
flatpak install --user --assumeyes build/leb2-watch.flatpak
flatpak info --user --show-permissions dev.oangsa.leb2watch
flatpak run --command=sh dev.oangsa.leb2watch -c \
  'test -x /app/bin/leb2-watch && test -L /app/lib/libappindicator3.so.1 && \
   ldd /app/bin/lib/libtray_manager_plugin.so | grep libappindicator3' \
  # in-sandbox file/linker smoke
timeout --signal=TERM 20s flatpak run dev.oangsa.leb2watch  # Wayland launch
jarsigner -verify <aab>          # exit 0, jar verified
jarsigner -verify -strict -certs # exit 4, self-signed signer
```

Flatpak preview results:

```text
flatpak-builder: PASS; manifest built with the Freedesktop 25.08 SDK/runtime
flatpak build-bundle: PASS; build/leb2-watch.flatpak created
flatpak install --user: PASS; dev.oangsa.leb2watch installed
flatpak info --user: PASS; command, runtime, narrow permissions, and metadata
in-sandbox smoke: PASS; executable, metadata, icon, AppIndicator symlink, and
  Flutter/AppIndicator/dbusmenu linker resolution were present
Wayland launch: PASS; process stayed alive for the bounded 20-second window;
  termination exit 124 was expected, with only cursor-theme/deprecation warnings
```

The current package input was the complete Linux bundle whose compile-time
backend origin was development-only `http://localhost:5015`. Its bounded
Wayland and packaged-autostart command launches passed under the current
KDE/Wayland session. The host and installed Flatpak sandbox both reached the
Swagger endpoint and received HTTP 200; unauthenticated `/Semester` requests
returned HTTP 401 in both namespaces. No authenticated API flow or real
login/reboot launch was run; this does not validate a production backend or
every newly changed Dart path.

Current continuation checks on 2026-08-01 passed the 20 focused desktop
autostart/tray tests, Flutter analysis, formatting of the eight changed Dart
files, manifest/desktop/AppStream validation, and `git diff --check`. The
memory-safe runner discovered 141 files in 15 shards but stopped in shard 8
after 12 failures in `deadline_reminder_convergence_test.dart`; an exact-file
rerun reproduced those failures. Direct Dart analysis could not initialize the
`riverpod_lint` analyzer plugin because the restricted host could not reach
`pub.dev`; Flutter analysis completed with no issues. This is not full-suite
pass evidence for the current dirty tree.

### Tests

- Native static coverage requires `SetQuitOnClose(true)`, rejects the old false
  setting, verifies the `Local\` mutex precedes Dart, and checks the stable
  app-specific window class and second-instance activation.
- Coordinator coverage verifies show-before-focus and bounded focus denial
  while preserving healthy tray Open and explicit Quit coverage. It also
  verifies failed window initialization requests conventional close.
- Adapter coverage verifies non-intercepting pre-run startup,
  listener-before-prevention ordering, conventional-close rollback, listener
  setup failure, and the guarded listener fallback when rollback also fails.
- Reveal-subscription coverage verifies request forwarding and post-disposal
  detachment.
- App coverage verifies reveal is requested before assignment-detail routing.
- Capability coverage verifies unpackaged launch-payload support is false and
  future packaged capability remains true.
- Process-delivery coverage verifies unpackaged-Windows composition, durable
  event planning, current-policy claims, retry fencing, and explicit disposal.
- Workflow static coverage verifies the pinned Flutter version, Windows host,
  desktop setup, sanitized definitions, Release build, complete-directory
  check, and absence of GitHub secret interpolation.

### Validation evidence

The feature began with one consolidated red batch. It failed on all intended
gaps: native quit-on-close was false, the coordinator operation was private,
the reveal signal/provider/subscription did not exist, unpackaged launch
payload was true, and no Windows build job existed.

After implementation:

```text
Focused Windows/desktop/app/notification regressions: 31 passed.
Combined desktop, app, and notification suites: 283 passed.
Full serialized Flutter suite: 979 passed.
Mocked Linux desktop integration workflow: 2 passed.
dart analyze --fatal-infos --fatal-warnings: no issues.
flutter analyze --fatal-infos --fatal-warnings: no issues.
dart format --output=none --set-exit-if-changed .:

*See [architecture](#architecture), [contracts](#contracts-and-interfaces), [limitations](#known-limitations), and [validation evidence](#validation-evidence); this compact retains the applicable continuation facts.*

## Cross-links

- Related: [notifications](../notifications/COMPACT.md) — Linux notification and tray validation
- Related: [synchronization](../synchronization/COMPACT.md) — Android background sync validation
- Related: [deletion](../deletion/COMPACT.md) — Android native deletion validation
- Related: [infrastructure](../infrastructure/COMPACT.md) — Flutter project scaffold targets all platforms

---

*Auto-compacted from 11 source files. Retained details are in this compact and its linked feature areas.*
