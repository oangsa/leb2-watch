# iOS Background Refresh

## Status

Implemented with an app-owned BGTaskScheduler registration that delegates to
the pinned Workmanager native handler and cooperatively forwards native
expiration into the existing Dart/service/Dio cancellation path. Dart and
static native tests pass on Linux. The Swift target, actual BGTask expiration,
and device cancellation timing are not build- or runtime-verified because the
current host has no Xcode.

## Purpose

Request best-effort local assignment refresh while LEB2 Watch is not in the
foreground, without promising exact execution or creating a second
synchronization path.

## Scope

- One `BGAppRefreshTask` identifier:
  `dev.oangsa.leb2watch.assignment-refresh`.
- Workmanager initialization, same-identifier scheduling, scoped
  cancellation, and headless plugin registration.
- The existing local-first `BackgroundSyncTaskExecutor` and
  `SyncReason.backgroundTask`.
- A conservative 25-second active-synchronization budget.
- Exact-generation native expiration latching and a headless-only
  attach/expired/detach MethodChannel.
- A per-invocation Dart cancellation lease with bounded attach and detach.
- Chaining of Workmanager's installed expiration handler so its Operation
  cancellation and task-completion behavior remain intact.
- Background-refresh availability and exact pending-request status through a
  narrow native MethodChannel.
- `fetch` background mode and one permitted task identifier.
- iOS deployment floor raised from 13.0 to 14.0 for Workmanager Apple 0.9.1+2.
- Root-owned `appResume` fallback behavior and dashboard-owned `appLaunch`
  synchronization supplied by the existing application lifecycle.

## Non-scope

- A custom headless Flutter engine or Workmanager fork.
- A `BGProcessingTask`, `processing` background mode, external-power
  requirement, or network constraint.
- Exact-time background execution, a precise next-check time, or a guarantee
  that iOS runs a pending request.
- Push notifications, remote persistence, analytics, or credentials in task
  metadata.
- Android WorkManager or desktop timer/tray behavior.
- Settings or diagnostics UI.

## User-visible behavior

When monitoring is enabled and the session is active, LEB2 Watch submits one
best-effort refresh request. Repeated submissions use the same identifier and
replace the unexecuted request instead of accumulating jobs. iOS may delay the
request for hours or omit it.

Opening or returning to the app remains a foreground refresh fallback. When
Background App Refresh is denied or restricted, status is reported as
unavailable. A pending request is only evidence that the OS currently retains
an unexecuted request; it is not an execution-time promise.

## Architecture

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
`false`, but the pinned iOS Workmanager implementation uses that value only
for its fetch/debug result. It ignores ordinary Dart failure when deciding
`BGTask.setTaskCompleted`.

AppDelegate owns the single BGTaskScheduler registration. For every delivered
`BGAppRefreshTask`, it creates a lowercase UUID generation, calls the pinned
public `WorkmanagerPlugin.handlePeriodicTask`, captures the expiration handler
installed synchronously by Workmanager, and replaces it with a one-shot
chain. The chain first marks the exact generation expired and then invokes
Workmanager's original handler. Workmanager therefore continues to resubmit
the next request, create and destroy its headless engine, cancel its native
Operation, and call `setTaskCompleted`.

`BackgroundRefreshExpirationCoordinator` protects its current generation,
latched expiration bit, and weak headless notifier with `NSLock`. A stale
expiration or detach cannot affect a replacement generation. The
`BackgroundRefreshExpirationBridge` plugin is registered only inside
Workmanager's headless plugin-registrant callback, never into the foreground
implicit engine. Native-to-Dart messages are dispatched on the main queue.

The Dart MethodChannel handler is installed before `attach`. A matching event
that races the attach reply is buffered; `expired: true` in the reply handles
expiration before the engine attached. Only a well-formed UUID matching the
owned lease can complete cancellation. Duplicate completion is idempotent.
Attach is bounded at one second. Detach is best effort and bounded at 500 ms;
a later native `begin` also supersedes an old record.

`BackgroundRefreshStatusBridge` is an app-owned foreground Flutter plugin in
`AppDelegate.swift`. Method `getStatus` returns only:

```text
backgroundRefreshStatus = available | denied | restricted | unknown
pending = true | false for the exact LEB2 Watch identifier
```

## Important files

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

## Contracts and interfaces

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

```text
available + pending     -> BackgroundScheduleActive(next = null)
available + not pending -> BackgroundScheduleInactive
denied/restricted       -> unavailable(registrationFailed)
unknown/bridge failure  -> unavailable(statusReadFailed)
```

## Data model

No SQLite schema or credential representation changes. Workmanager stores its
Dart callback handle in platform preferences. The task name and MethodChannel
payload contain no semester, user, cookie, password, assignment, or backend
response data.

Global desired state, install jitter, active target, session state, course
policy, backoff, and synchronization history remain in the Feature 13.1 local
database contracts.

## State and control flow

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

## Platform behavior

This feature affects iOS only. The iOS target floor is 14.0. `UIBackgroundModes`
contains only `fetch`; `processing` is absent. No extra entitlement is added.

BGAppRefresh is best effort. Background Refresh may be denied or restricted,
Low Power Mode may reduce opportunities, and simulator scheduling is not
representative. Apple's development launch/expiration commands require a
physical device.

## Security and privacy

The callback receives no input data and reads the current target from local
SQLite. Credentials remain in `flutter_secure_storage` with the existing iOS
accessibility policy. Before first unlock, secure-storage failure becomes a
safe failed attempt; there is no plaintext fallback.

No task identifier, plist value, MethodChannel message, log, or status result
contains credentials, authorization headers, response bodies, assignment
content, or personal identifiers. Notifications remain local and post-commit.

## Decisions

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

## Alternatives rejected

- `processing` mode and BGProcessingTask solve a different idle-time workload.
- `cancelAll` could remove unrelated future work.
- Passing target IDs or credentials as Workmanager input would become stale
  and violate local-source-of-truth/privacy boundaries.
- `printScheduledTasks` is debugging output, not a production status API.
- A custom BGTask/headless-engine implementation would add substantial native
  lifecycle and cancellation code beyond the approved scope.
- Polling a preference or file would waste limited background time and still
  leave an attach race.
- An EventChannel adds stream lifecycle without removing the required native
  latch.
- A local Workmanager fork could remove the handler-takeover window, but would
  add ongoing dependency maintenance; an upstream hook is preferable.

## Failure behavior

Malformed or failed native status reads return a redacted unavailable status.
Initialization may be retried after failure. Registration and cancellation
errors flow through the shared scheduler categories while saved desired state
remains authoritative.

Handler startup, storage, transport, invalid-response, or cancellation results
return the app's Dart `false` value. Durable backoff deferral returns Dart
`true` because local policy intentionally skipped the request.
Session-paused/missing-target/disabled paths cancel the exact next request and
return Dart `true` when cancellation succeeds.

Pinned Workmanager converts Dart `false` into a failed fetch/debug result, but
`BackgroundTaskOperation` ignores that result. Its BGTask completion block uses
only `!operation.isCancelled`, so ordinary app failures are reported to iOS as
native success. The app does not own a safe generation-fenced native
failure-control API and does not pretend otherwise.

Bridge attach failure or timeout returns Dart `false` without opening the
headless sync composition. A malformed native response or generation is
rejected without exposing its value. Detach failures/timeouts are bounded and
best effort because a later native generation supersedes the old state.

When Apple expires an attached task, the native latch completes the matching
Dart cancellation. The shared runner requests `cancelCurrent`, which reuses
the existing service and Dio cancellation ownership; there is no alternate
sync path. Workmanager's original expiration closure is always called by the
one-shot chain. This actual native callback cancels Workmanager's Operation,
so its completion block reports the BGTask unsuccessful after Dart returns.
If Workmanager did not install a handler, AppDelegate directly fails the
BGTask instead of leaving it unfinished.

## Tests

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
  unsupported query;
- exact-task lease injection, unknown-task bypass, fail-before-sync attach
  behavior, pre-cancel zero-work detach, live pending-handler cancellation,
  late success/error observation, delayed composition/policy ownership,
  no-HTTP fencing, cancellation mapping, `finally` close for
  stop/success/failure, stale-lease isolation, the active-sync 25-second
  budget, and top-level VM retention;
- pure Swift generation uniqueness, pre-attach latching, live/duplicate
  expiration, stale expiration/detach fencing, one-shot original handler, and
  refresh-status enum mapping in `RunnerTests`.

## Validation evidence

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

## Known limitations

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
  Workmanager may tear down the expiring headless engine before the retained
  Dart cleanup continuation completes.
- Without native expiration, composition opening and local policy reads have
  no 25-second deadline. The active-sync budget begins later. When native
  expiration does occur, the outer Dart callback returns promptly and the
  late handler stays observed, but Workmanager may destroy the engine before a
  late startup continuation gets another chance to close resources. Device
  validation must measure this teardown path.
- Ordinary Dart `false` results do not make the pinned native BGTask fail.
  Only actual Apple expiration cancels Workmanager's Operation; missing-handler
  and wrong-task-type guards are direct native failures.
- Pending status does not guarantee execution.
- iOS has no equivalent to Android WorkManager's connected-network
  constraint for BGAppRefresh.
- Exact execution time is unknowable.

## Future considerations

- Validate the complete callback on a physical iOS device.
- Prefer a future upstream Workmanager expiration hook, which would remove the
  handler-takeover interval without a local fork.
- Re-audit the pinned native integration before any Workmanager upgrade.

## Required macOS and device validation

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
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16'
flutter devices
flutter run -d <PHYSICAL_IOS_DEVICE_ID> \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=<TEST_BACKEND_BASE_URL>
```

On a physical device, use Apple's development-only debugger commands:

```text
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"dev.oangsa.leb2watch.assignment-refresh"]
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"dev.oangsa.leb2watch.assignment-refresh"]
```

These private selectors must never appear in shipped application source.

## Related contexts

- `docs/contexts/background-scheduler.md`
- `docs/contexts/assignment-synchronization.md`
- `docs/contexts/synchronization-backoff.md`
- `docs/contexts/session-expiration.md`
- `docs/contexts/local-notifications.md`
- `docs/contexts/deadline-reminders.md`
- `docs/contexts/course-preferences.md`
