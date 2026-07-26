# iOS Background Refresh

## Status

Implemented with stock Workmanager/BGTaskScheduler and host-runnable static
validation. Not build-verified on iOS because the current host is Linux.
Stock Workmanager's native expiration does not propagate into Dart/Dio
cancellation; physical-device expiration behavior remains unverified.

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
- A conservative 25-second app-owned watchdog.
- Background-refresh availability and exact pending-request status through a
  narrow native MethodChannel.
- `fetch` background mode and one permitted task identifier.
- iOS deployment floor raised from 13.0 to 14.0 for Workmanager Apple 0.9.1+2.
- Root-owned `appResume` fallback behavior and dashboard-owned `appLaunch`
  synchronization supplied by the existing application lifecycle.

## Non-scope

- A custom BGTaskScheduler/headless Flutter engine.
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

`iosBackgroundCallbackDispatcher` is a top-level VM entrypoint. It installs
one exact-name handler through the shared Workmanager dispatcher.
`IosBackgroundSyncTaskHandler` opens the Feature 13.1 owned headless
composition and runs the shared synchronization service with a maximum
25-second time budget.

Workmanager resubmits the next BGAppRefresh request before Dart runs. The
handler therefore cancels that exact pending request when durable local policy
reports monitoring disabled, no target, or an inactive/expired session.
Success, durable backoff deferral, and no background-monitored courses leave
the next best-effort request intact. Failed/cancelled work returns the
Workmanager unsuccessful result.

The AppDelegate registers Workmanager's headless
`GeneratedPluginRegistrant` callback and the BGAppRefresh identifier before
returning from application launch. Foreground plugins remain registered by
`didInitializeImplicitFlutterEngine`; the notification-center delegate remains
unchanged.

`BackgroundRefreshStatusBridge` is an app-owned foreground Flutter plugin in
`AppDelegate.swift`. Method `getStatus` returns only:

```text
backgroundRefreshStatus = available | denied | restricted | unknown
pending = true | false for the exact LEB2 Watch identifier
```

## Important files

- `lib/src/platform/background/ios/ios_background_contract.dart` — exact task
  identity and 25-second watchdog.
- `lib/src/platform/background/ios/ios_background_callback.dart` — retained
  dispatcher and result policy.
- `lib/src/platform/background/ios/ios_workmanager_scheduler_platform.dart` —
  shared scheduler adapter.
- `lib/src/platform/background/ios/ios_background_refresh_status_bridge.dart`
  — typed MethodChannel boundary.
- `lib/src/platform/background/families/ios_background_scheduler_factory.dart`
  — iOS family wiring.
- `ios/Runner/AppDelegate.swift` — launch registration, headless registrant,
  and native status bridge.
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
5. Workmanager resubmits the next request, creates a headless engine, and
   invokes the exact Dart dispatcher.
6. The handler opens fresh provider/database ownership and runs the shared
   background runner with a 25-second budget.
7. The runner performs local gates before HTTP and reuses durable
   single-flight, backoff, cache, session-expiration, notification, and
   deadline-reminder behavior.
8. Stop gates cancel only the exact resubmitted request.
9. The owned composition closes after synchronization is terminal. If the
   25-second watchdog wins and cancellation does not settle within the shared
   one-second drain, task completion remains bounded while a retained
   close-after-quiescence continuation keeps the database open until both the
   cancellation request and original synchronization are terminal.

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
- Add a conservative 25-second Dart watchdog as risk reduction, not as a
  native-expiration signal.
- Preserve Feature 13.1 foreground lifecycle fallbacks.

## Alternatives rejected

- `processing` mode and BGProcessingTask solve a different idle-time workload.
- `cancelAll` could remove unrelated future work.
- Passing target IDs or credentials as Workmanager input would become stale
  and violate local-source-of-truth/privacy boundaries.
- `printScheduledTasks` is debugging output, not a production status API.
- A custom BGTask/headless-engine implementation would add substantial native
  lifecycle and cancellation code beyond the approved scope.

## Failure behavior

Malformed or failed native status reads return a redacted unavailable status.
Initialization may be retried after failure. Registration and cancellation
errors flow through the shared scheduler categories while saved desired state
remains authoritative.

Handler startup, storage, transport, invalid-response, or cancellation results
complete the Workmanager task unsuccessfully. Durable backoff deferral is
handled successfully because local policy intentionally skipped the request.
Session-paused/missing-target/disabled paths cancel the exact next request and
complete successfully when cancellation succeeds.

Stock Workmanager installs a native `expirationHandler` that cancels its
`Operation` and completes the BGTask unsuccessfully. Its operation waits for
Dart and does not propagate actual native expiration to
`BackgroundSyncCancellation` or Dio. The 25-second watchdog normally calls
the shared runner's `cancelCurrent`, but Apple may expire earlier. This feature
must not be described as fully cooperative native-expiration cancellation.

## Tests

Host-runnable tests cover:

- exact Info.plist identifier and `fetch`-only mode;
- launch registration order and preserved foreground/headless registrants;
- all Runner deployment targets at iOS 14.0 and unchanged bundle ID;
- MethodChannel available/denied/restricted/malformed responses;
- joined Workmanager initialization;
- stable scheduling identity, first delay, no iOS network constraint, and
  update policy;
- exact cancellation and native pending status without Workmanager's
  unsupported query;
- callback stop-gate cancellation, success/deferral preservation, failure
  mapping, 25-second budget, and top-level VM retention;
- native refresh-status enum mapping in `RunnerTests`.

## Validation evidence

On Linux:

- the four focused Dart/static files passed 13/13 tests;
- strict owned-path Dart analysis passed with no issues;
- owned-path format verification reported 9 files and 0 changes;
- `xmllint` accepted Info.plist, both entitlements, and
  AppFrameworkInfo.plist;
- `git diff --check` passed;
- the owned-path secret scan found no matches;
- the repository-wide Flutter suite passed 766 tests and failed only the
  integration-owned shared factory test, whose pre-integration expectation
  still requires every platform family to be an unsupported stub;
- repository-wide strict analysis reached only desktop Feature 13.4 findings
  (12 unique lints) and reported no iOS finding.

The iOS build and native test were not run because this host has no Xcode.

## Known limitations

- iOS build, Swift type checking, signing, BGTask execution, Keychain access,
  Drift headless access, notifications, and forced expiration are unverified.
- Stock Workmanager native expiration does not notify Dart cancellation.
- Pending status does not guarantee execution.
- iOS has no equivalent to Android WorkManager's connected-network
  constraint for BGAppRefresh.
- Exact execution time is unknowable.

## Future considerations

- Validate the complete callback on a physical iOS device.
- Adopt a future Workmanager expiration-to-Dart signal if one becomes
  available.
- Reconsider a custom native engine only if cooperative early expiration
  becomes a hard release requirement.

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
