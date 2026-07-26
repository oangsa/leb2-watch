# Local Notification Service

## Status

Completed for Feature 12.1, with Feature 12.2 supplying a durable retryable
new-assignment outbox and Feature 12.3 supplying durable deadline-reminder
ownership and reconciliation. The application-owned service, platform
adapter, validated assignment targets, navigation coordinator, Android native
setup, iOS delegate setup, tests, and Linux release build are implemented.
Android, iOS, macOS, and Windows native builds remain unverified on this Linux
host.

## Purpose

Give LEB2 Watch one local-only boundary for displaying assignment updates,
scheduling supported deadline reminders, requesting permission after an
explanation, and opening a saved assignment from a notification without
exposing plugin types to application callers.

## Scope

- Idempotent and concurrent-safe local-notification initialization.
- Deferred Android, iOS, and macOS permission requests.
- Passive delivery-permission reads that never display a prompt.
- Fixed test-notification copy.
- Bounded new-assignment and deadline-reminder requests.
- Immediate notification display on supported platforms.
- UTC one-shot reminder scheduling where cancellation is supportable, with
  device-local deadline copy and an explicit UTC offset.
- App-owned permission, failure, request, target, owner, and ID types.
- Versioned payload parsing to `AssignmentDetailKey`.
- Deterministic versioned int32 ID candidate sequences.
- Running-process and supported cold-launch response handling.
- Flow-gated assignment-detail navigation.
- Stable Android channels and per-course grouping.
- Android desugaring, reboot receivers, and retained notification icon.
- Required iOS notification-center delegate.
- Non-placeholder Windows initialization identity.

## Non-scope

- Deciding whether a synchronized assignment is new.
- Baseline, dedupe, history-write, or notification-delivery orchestration.
- Persisting or transactionally allocating notification IDs.
- Reminder offsets, reconciliation, limits, or removal policy; Feature 12.3
  owns those concerns behind this service.
- Global or per-course notification setting decisions.
- Notification settings UI or permission explanation UI.
- Android WorkManager, Apple background tasks, desktop timers, tray, or
  autostart.
- Exact alarms, full-screen intents, actions, foreground services, DND bypass,
  critical alerts, badges, custom sounds, attachments, push, analytics, or
  backend calls.
- Linux DBus activation or Windows MSIX packaging.
- Drift schema or migration changes.

## User-visible behavior

Initialization occurs during app startup but never prompts for permission. A
future explained, user-initiated workflow can request permission through the
service. A test notification says that local notifications are working.

New-assignment copy contains the bounded course name, assignment title, and a
verified deadline when present. Reminder copy contains the course, assignment,
and saved deadline. Deadline instants remain UTC internally but render in the
device timezone with an explicit offset such as `UTC+07:00`. Selecting a valid
assignment notification opens the existing local detail route. If onboarding,
authentication, or semester selection is active, the newest valid target waits
until the flow is ready and then opens exactly once. Each live OS response
callback remains actionable, even when two callbacks carry the same target.

Unsupported scheduling or cancellation is reported as unsupported. The
service never silently claims that a Linux reminder was scheduled or that an
unpackaged Windows notification can be cancelled.

## Architecture

`LocalNotificationService` is the plugin-free application boundary.
`LocalNotificationServiceImpl` validates requests, composes fixed copy,
encodes targets, maps permission and platform failures, joins concurrent
initialization, exposes passive delivery-permission state and attempt-scoped
abandonment to bounded application
orchestrators, and publishes a broadcast response stream.

`LocalNotificationsPlatform` is an injected application-owned adapter seam.
`FlutterLocalNotificationsAdapter` is the only production file that imports
`flutter_local_notifications` and `timezone`. It maps application values into
platform details, channels, thread/group/header metadata, UTC schedules, and
permission calls.

`NotificationNavigationCoordinator` subscribes before plugin initialization.
It holds at most one pending target, listens to `AppFlowController`, and calls
the named assignment-detail route only when the flow is ready.
`Leb2WatchApp` owns and disposes this coordinator. Riverpod owns and disposes
the notification service.

## Important files

- `lib/src/features/notifications/domain/local_notification_models.dart` —
  plugin-free requests, owners, IDs, targets, permissions, and failures.
- `lib/src/features/notifications/domain/local_notification_service.dart` —
  application-owned service and initialization-attempt interfaces.
- `lib/src/features/notifications/domain/local_notification_payload_codec.dart`
  — strict versioned assignment-target codec.
- `lib/src/features/notifications/domain/local_notification_id_factory.dart` —
  deterministic candidate sequence and reserved test ID.
- `lib/src/features/notifications/data/local_notifications_platform.dart` —
  app-owned platform capability and operation seam.
- `lib/src/features/notifications/data/flutter_local_notifications_adapter.dart`
  — concrete Flutter plugin translation.
- `lib/src/features/notifications/application/local_notification_service_impl.dart`
  — validation, copy composition, response handling, and failures.
- `lib/src/features/notifications/application/local_notification_deadline_formatter.dart`
  — deterministic device-local deadline rendering with an explicit UTC offset.
- `lib/src/features/notifications/application/notification_navigation_coordinator.dart`
  — app-flow-gated local navigation.
- `lib/src/app/app_dependencies.dart` — Riverpod composition and ownership.
- `lib/src/app/leb2_watch_app.dart` — startup initialization and router
  coordination.
- `android/app/src/main/AndroidManifest.xml` — reboot permission and exactly
  the two scheduling receivers.
- `android/app/src/main/res/drawable/ic_notification.xml` — monochrome status
  icon.
- `ios/Runner/AppDelegate.swift` — notification-center delegate assignment.
- `test/features/notifications/` — domain, service, adapter, and coordinator
  tests.
- `test/platform/local_notifications_native_config_test.dart` — dependency and
  native configuration assertions.

## Contracts and interfaces

```dart
abstract interface class LocalNotificationService {
  Stream<LocalNotificationTarget> get responses;
  Future<void> initialize();
  Future<NotificationDeliveryPermissionStatus> readDeliveryPermission();
  Future<NotificationPermissionStatus> requestPermission();
  Future<void> showTestNotification();
  Future<void> showNewAssignment(NewAssignmentNotification request);
  Future<void> scheduleDeadlineReminder(
    DeadlineReminderNotification request,
  );
  Future<void> cancelReminder(LocalNotificationId id);
  Future<void> cancelAll();
  void dispose();
}

abstract interface class LocalNotificationInitializationAttempt {
  Future<void> get completion;
  void abandon();
}

abstract interface class LocalNotificationInitializationControl {
  LocalNotificationInitializationAttempt beginInitializationAttempt();
}
```

The attempt-control seam is optional to notification callers. Normal
`initialize()` delegates to it. Concurrent callers receive handles for one
shared active attempt. Only the holder of the exact active attempt can abandon
it; returned failures reset it for retry, and success remains retained.

Payloads are deterministic JSON with exactly:

```json
{"v":1,"type":"assignment","semesterId":123,"identityKey":"backend:456"}
```

The UTF-8 payload and Dart string are each limited to 512 units. The root must
contain exactly the four supported fields and types. Semester and identity are
reconstructed only through `AssignmentDetailKey.tryParse`; arbitrary routes,
extra fields, other versions/types, non-int numeric values, malformed JSON,
and invalid identities are ignored.

Display values normalize whitespace and are bounded to 80 characters for a
course and 160 for a title. Remaining C0/C1 controls, Arabic Letter Mark,
left/right marks, bidi embeddings/overrides, and bidi isolates are rejected
before platform I/O; ordinary Unicode and emoji remain valid. Course IDs are
positive int32. Every request ID must own the same assignment, kind, and
reminder offset as the request. Instants must be UTC; a schedule must be future
and exactly its declared positive offset before the deadline.

## Data model

The service itself owns no database table. Feature 12.3 adds
deadline-reminder preferences and durable reconciliation. New-assignment
delivery hardening adds the schema-v11 retryable outbox. A successful plugin
future is treated as accepted platform submission, never proof of OS display
or user delivery.

The canonical candidate owner keys are:

```text
leb2-notification:v1:new:<semesterId>:<identityKey>
leb2-notification:v1:deadline:<semesterId>:<identityKey>:<offsetMinutes>
```

For each nonnegative probe, the factory hashes
`ownerKey + NUL + decimalProbe` with SHA-256, reads the first unsigned
big-endian word, masks it to 31 bits, and skips zero and reserved ID
`2147483646`. Assignment IDs may use the remaining full positive int32 range,
including `2147483647`. The factory returns a candidate sequence rather than
claiming the truncated mapping is collision-free.

Feature 12.2 resolves the new-assignment sequence against
`notification_history`, `new_assignment_notification_outbox`, and
`scheduled_reminders` inside its persistence transaction and uses the
canonical owner key as its dedupe key. Retries reuse the outbox ID. Feature
12.3 applies the same collision rule for deadline reminders and persists
ownership before platform I/O. The platform service itself neither reads nor
writes those rows.

`DriftLocalNotificationIdAllocator` owns this shared three-table collision
probe for both new-assignment delivery and global-disable suppression.

## State and control flow

1. Riverpod creates one platform adapter and one local service.
2. `Leb2WatchApp` creates the router and response coordinator.
3. The coordinator subscribes before service initialization.
4. Concurrent initialization callers join one attempt and one completion
   future.
5. The adapter registers one main-isolate response callback without prompting.
6. Initialization becomes ready only after adapter initialization and the
   supported cold-launch lookup both succeed; either failure resets the whole
   operation for a retry.
7. A supported cold-launch payload is consumed once through the retained
   successful initialization attempt.
8. Every distinct live callback is decoded and emitted, including repeated
   callbacks carrying the same valid target.
9. A ready flow navigates immediately; a gated flow retains the newest target.
10. Becoming ready consumes the pending target before navigating, preventing
   reentrant duplicate delivery.
11. A coordinator timeout may abandon only its captured active initialization
    attempt. A later caller may replace it even if the underlying platform
    Future cannot be cancelled. Every state mutation and launch-payload
    delivery is identity-fenced, so late abandoned success or error cannot
    clear or replace newer readiness.
12. App disposal removes flow and stream listeners; provider disposal closes
    the service response stream and adapter bridge. Disposal is checked before
    platform entry and after every initialization await, so queued or in-flight
    work cannot enter the platform after teardown or become ready.

Permission requests, showing, scheduling, and cancellation require successful
initialization. A failed initialization may be retried.

## Platform behavior

- **Android:** immediate notifications, permission request, launch response,
  inexact one-shot UTC scheduling, cancellation, reboot restoration receivers,
  and stable `leb2_assignment_updates_v1` /
  `leb2_deadline_reminders_v1` channels. No exact-alarm permission is used.
- **iOS:** immediate notifications, deferred alert/sound permission, launch
  response, one-shot UTC scheduling, and cancellation. Badge, provisional,
  critical, and CarPlay requests are not made. The notification-center delegate
  is assigned before `super` returns.
- **macOS:** the same immediate, deferred alert/sound permission, launch,
  one-shot UTC scheduling, and cancellation contract is translated by the
  shared adapter. Its plugin owns delegate registration.
- **Linux:** immediate show and same-process cancellation/response handling.
  Scheduling and cold-launch payload recovery are unsupported because the
  current runner is not DBus-activatable. The federated Linux plugin exposes
  no public teardown; the process-lifetime adapter instead guards callbacks
  after disposal.
- **Windows:** immediate show and launch response. Scheduling and cancellation
  are enabled only when runtime package identity exists. The current
  unpackaged executable therefore reports both unsupported. Dart initialization
  uses app name `LEB2 Watch`, AppUserModelID
  `dev.oangsa.leb2watch.app`, and committed GUID
  `9be8a9ac-9c1d-45c5-a3c0-a8189e5d0d55`; no MSIX was added. Adapter disposal
  invokes the Windows federated plugin's public `dispose()` exactly once.

Android, Darwin, and Windows use the course group key
`leb2.course.<semesterId>.<courseId>` where supported. Linux does not claim
cross-server grouping.

## Security and privacy

Credentials, authorization headers, backend URLs, assignment descriptions,
opaque backend JSON, and diagnostics never enter a notification payload. The
payload contains only the non-secret local semester and stable assignment
identity required to open cached detail.

Callers cannot provide arbitrary notification bodies, actions, XML/HTML,
routes, or raw payloads. Public debug output for requests, IDs, owners,
targets, platform requests, the codec, and failures is bounded and redacted.
Platform exceptions are replaced with fixed application-owned failures and
are never logged.

Invalid or oversized response payloads are ignored without echoing their
content. App startup catches notification-bridge failure without logging it
and continues to show local cached data.

## Decisions

- Keep every plugin type behind one application-owned adapter.
- Initialize at startup but defer all permission prompts.
- Represent taps as validated assignment targets rather than route strings.
- Preserve the newest target outside `GoRouter` while flow guards are active.
- Use UTC one-shot schedules because saved verified deadlines are instants.
- Render user-visible deadline copy through the device timezone with an
  explicit offset while preserving UTC scheduling instants.
- Treat every live response callback as a user action; only launch-detail
  lookup is one-shot through successful initialization.
- Use ordinary inexact Android scheduling rather than special exact-alarm
  access.
- Expose a deterministic candidate sequence and explicit owner validation
  instead of calling a truncated hash collision-free.
- Reserve one fixed test ID outside assignment ownership.
- Disable unsupported unpackaged-Windows scheduling rather than create a
  reminder that the app cannot reliably cancel.
- Keep collision allocation and notification history persistence in their
  later owning features.

## Alternatives rejected

- Plugin types in widgets or synchronization code: this would couple business
  logic to platform APIs and expose raw failures.
- Arbitrary deep-link strings: payloads could escape the local route contract.
- Exact Android alarms: assignment reminders do not justify special alarm
  access or exact-time promises.
- A timezone database plugin for display: Dart's device-local projection plus
  an explicit UTC offset renders honest local copy without another plugin.
- Treating a 31-bit hash as unique: the assignment/offset domain is larger
  than the ID range.
- A new allocation table: existing later-feature history/reminder ownership
  can resolve collisions transactionally.
- Linux runner DBus changes or Windows MSIX packaging: both belong to desktop
  monitoring/packaging work.
- Persisting responses or targets: flow coordination is process-local and
  contains no durable business state.

## Failure behavior

- Operations before initialization or after disposal fail with
  `notInitialized`.
- Invalid ownership, bounds, unsafe display controls, non-UTC times, past
  schedules, or inconsistent offsets fail with `invalidRequest` before
  platform interaction.
- A plugin initialization result other than `true` maps to
  `platformUnavailable` and permits a later retry.
- Launch-detail lookup failure maps to `platformFailure`, leaves the service
  unready, and permits a complete later retry.
- Explicit abandonment maps that attempt's completion to a redacted
  `platformFailure` and permits replacement. The non-cancellable underlying
  Future is contained; its late success, error, or launch payload cannot mutate
  a newer successful attempt.
- Linux scheduling and unpackaged-Windows scheduling/cancellation fail with
  `unsupported`.
- Platform exceptions map to `platformFailure` without raw details.
- Permission requests return `granted`, `denied`, `unavailable`, or
  `notRequired`; a denial is not confused with initialization or transport
  failure.
- Invalid or unsupported response payloads are ignored. Repeated live valid
  callbacks are emitted rather than deduplicated.
- Startup initialization failure does not block cached UI or trigger a
  permission prompt.

## Tests

- Model tests cover owner invariants, valid ID bounds, the reserved ID, complete
  permission/failure vocabulary, and redacted diagnostics.
- ID tests cover the known SHA-256 candidate, determinism, collision-probe
  advancement, owner-field sensitivity, range, and reserved-ID exclusion.
- Payload tests cover backend/fingerprint round trips, deterministic encoding,
  malformed/trailing/oversized/extra/wrong-type/version/key rejection, UTF-8
  bounds, and redaction.
- Service tests cover concurrent/retry initialization, atomic launch lookup,
  disposal before platform entry and during platform/launch waits,
  launch-once/live-repeat response handling, no implicit permission, permission
  mapping, fixed test copy, device-local deadline copy, new-assignment
  grouping/content, UTC inexact reminders, display-control rejection,
  Unicode/emoji preservation, validation-before-I/O, unsupported platforms,
  cancellation, bounded platform failures, and disposal.
- Deadline-reminder convergence tests exercise the production service wrapper
  across bounded initialization and launch-payload timeouts, second-owner
  replacement, and late abandoned success/error fencing.
- Deadline formatter tests cover deterministic positive and negative
  half-hour UTC offsets.
- Adapter tests cover Darwin permission flags, Android icon, Windows identity,
  capability matrices, idempotent Windows teardown, and Linux's lack of
  teardown.
- Coordinator tests cover ready navigation, all flow gates, newest-target
  replacement, explicit semester identity, exactly-once delivery, and
  disposal.
- Root/provider tests cover service composition, lifecycle ownership, startup
  initialization, real named-route integration, and post-disposal detachment.
- Static native tests cover dependency pins/registrants, desugaring, boot
  permission/actions/receivers, prohibited Android privileges/components,
  icon retention, inexact mode, and iOS delegate ordering.

## Validation evidence

Flutter/Dart tooling first ran after sourcing `~/.zshrc` once, as requested.

- `flutter pub get` — passed; resolved exact
  `flutter_local_notifications 22.2.0` and `timezone 0.11.1`.
- Focused Feature 12.1 aggregate — 59 tests passed.
- Independent adversarial regression file — 3 tests passed.
- `dart run build_runner build --delete-conflicting-outputs` — passed; the
  first pass completed and the immediate stability pass wrote zero outputs.
  Generated-source hashes before and after both runs were identical. The
  documented removed-option warning remains expected.
- `dart format --output=none --set-exit-if-changed .` — passed; 158 files,
  zero changes.
- `dart analyze --fatal-infos --fatal-warnings` — passed with no issues.
- `flutter analyze --fatal-infos --fatal-warnings` — passed with no issues.
- `flutter test --reporter failures-only` — 573 tests passed.
- `flutter build linux --release` — passed; produced
  `build/linux/x64/release/bundle/leb2-watch`.
- `flutter build apk --release` — attempted but stopped before Gradle because
  this host has no Android SDK and no `ANDROID_HOME`; no APK success is
  claimed.
- Static Android/iOS/dependency/registration configuration tests — 4 passed.

## Known limitations

- Actual notification display, OS permission prompts, foreground/terminated
  taps, reboot rescheduling, OEM delay, and OS suppression need device testing.
- Android was statically validated but not built because the Android SDK is
  unavailable on this host.
- iOS, macOS, and Windows were not build-verified on their native toolchains.
- iOS retains at most 64 pending local notifications; Feature 12.3 enforces a
  deterministic global app-owned deadline-reminder cap, but other pending
  notification requests owned by LEB2 Watch remain application-capacity
  factors.
- Android/OEM and Apple policies may delay or suppress a scheduled reminder.
- Plugin success does not prove that the OS displayed or delivered a
  notification.
- Linux scheduling and cold-launch notification recovery remain unsupported.
- Current unpackaged Windows builds cannot reliably schedule-and-cancel
  reminders; MSIX runtime identity is required.
- New-assignment history proves a committed app-level show request or muted
  decision, not platform display or delivery. Deadline-reminder ready state
  likewise proves only that the latest app-level scheduling call returned.

## Future considerations

- Feature 12.3 owns reminder offset selection, iOS pending limits,
  persistence, reconciliation, rescheduling, and removal.
- Feature 14.1 should explain permission purpose and platform reliability
  before calling `requestPermission`.
- Feature 13.2 can reuse this service from Android background work after
  initializing Flutter, secure storage, and Drift correctly.
- Feature 13.4 may add Linux DBus activation and Windows packaging as explicit
  desktop work.
- Run `flutter build apk --release`, `flutter build ios --no-codesign`,
  `flutter build macos`, and `flutter build windows` on supported hosts.

## Related contexts

- [Assignment Detail](assignment-detail.md)
- [Adaptive Application Shell](adaptive-app-shell.md)
- [Assignment Diffing](assignment-diffing.md)
- [New-Assignment Notifications](new-assignment-notifications.md)
- [Local Database](local-database.md)
- [Flutter Dependencies and Code Generation](flutter-dependencies-and-codegen.md)
- [Course Preferences](course-preferences.md)
- [Deadline Reminders](deadline-reminders.md)
