# Notification Settings

## Status

Completed.

## Purpose

Give users one local-first place to control notification and monitoring
behavior without implying that an operating system can guarantee background or
reminder timing.

## Scope

- Persisted global background-monitoring intent and actual scheduler status.
- Persisted global new-assignment notification enablement.
- Persisted deadline reminder enablement plus the supported 24-hour and
  1-hour offsets.
- Navigation to existing per-course notification and monitoring controls.
- Desktop-only, OS-backed start-at-login control.
- Explicit notification permission and test-notification actions.
- Platform-specific best-effort and capability explanations.
- Real `/settings` routing with adaptive and accessible presentation.
- Schema v10, migration fixtures, enforcement, application, widget, router,
  and regression tests.

## Non-scope

- New background schedulers or platform workers.
- New notification adapters or reminder offsets.
- Duplicating the course-preference list.
- Tray/window behavior.
- Synchronization diagnostics.
- License or self-hosting documentation.
- Exact-time execution promises.

## User-visible behavior

The Settings destination now opens `Notification settings` instead of a
placeholder. Saved values are rendered from local streams and remain
authoritative while a write is pending. Only the affected control is disabled.
A failed write keeps the previous persisted value and shows fixed, live-region
feedback.

Background monitoring defaults off. Its switch represents saved user intent,
while secondary copy reports the platform schedule separately. New-assignment
notifications default on. Turning them off suppresses all currently unclaimed
discoveries and later discoveries without replaying them after re-enabling.

Deadline reminders and both supported offsets remain independently editable.
Turning reminders off preserves the selected offsets. Course-specific controls
open the existing Courses route.

Notification permission is never requested merely by opening Settings. The
explicit action first initializes notifications, then requests permission.
After a granted or not-required result, it best-effort drains pending
new-assignment work for the active semester without another backend request.
The test action reports that a request was submitted to the operating system,
not that delivery occurred.

Start at login appears only on Linux, macOS, and Windows. Platform reliability
copy explains mobile best-effort background scheduling, process-lifetime
desktop monitoring, Linux scheduling limits, and packaged/unpackaged Windows
differences.

## Architecture

`NotificationSettingsService` is a plugin-free facade over existing deep
modules:

- `BackgroundMonitoringSettingsService` owns persisted desired monitoring.
- `BackgroundScheduler` reports actual native scheduling status.
- `NewAssignmentNotificationPreferencesService` owns the new global policy.
- `DeadlineReminderPreferencesService` owns reminder policy and reconciliation.
- `DesktopAutostartService` owns OS start-at-login truth.
- `LocalNotificationService` owns permission and test actions.
- `NewAssignmentNotificationDrain` retries active-semester cached work after
  an explicit successful permission action.

`LocalNotificationSettingsService.watch()` combines those local streams
without adding a stream-combination dependency. Scheduler status read failure
becomes a fixed unavailable status so other saved preferences remain usable.
Errors from a durable settings stream become a redacted
`NotificationSettingsException`.

Actual scheduler status has its own event-driven update path. A successful
monitoring write publishes the authoritative
`BackgroundMonitoringUpdateApplied.status`. The root application requests one
status refresh after session reconciliation completes and after app-resume
work completes; the settings service then reuses
`BackgroundScheduler.getStatus()`. This does not poll and does not depend on
the desired-preference stream emitting.

Riverpod composition lives in
`notification_settings_dependencies.dart`. The presentation receives only
app-owned domain contracts and a small `NotificationSettingsPlatform` enum.
The page never imports Drift or platform plugins.

`NotificationSettingsPage` fences replacement subscriptions, keeps persisted
values authoritative, tracks pending work per control, and stores only
session-local permission/action feedback in widget state.

## Important files

- `lib/src/features/settings/notifications/domain/notification_settings.dart`
  — aggregate snapshot, platform reliability model, and safe exception.
- `lib/src/features/settings/notifications/domain/new_assignment_notification_settings.dart`
  — persisted global new-assignment value.
- `lib/src/features/settings/notifications/application/notification_settings_service.dart`
  — stream aggregation, write delegation, permission, and test actions.
- `lib/src/features/settings/notifications/application/new_assignment_notification_preferences_service.dart`
  — redacted preference application boundary.
- `lib/src/features/settings/notifications/data/new_assignment_notification_preferences_store.dart`
  — transactional Drift persistence and suppression.
- `lib/src/features/settings/notifications/notification_settings_dependencies.dart`
  — Riverpod composition.
- `lib/src/features/settings/notifications/presentation/notification_settings_page.dart`
  — adaptive settings interface.
- `lib/src/features/settings/notifications/presentation/notification_settings_route.dart`
  — local provider loading/error/retry boundary.
- `lib/src/features/background_sync/domain/background_scheduler.dart` —
  event-driven scheduler-status refresh signal and existing status contracts.
- `lib/src/app/leb2_watch_app.dart` — requests status refresh after completed
  session reconciliation and app-resume work.
- `lib/src/features/notifications/data/new_assignment_notification_store.dart`
  — claim-time global policy enforcement.
- `lib/src/core/database/database_tables.dart` — preference table introduced
  in schema v10 and retryable outbox introduced in schema v11.
- `lib/src/core/database/app_database.dart` — ordered v1–v10 to v11 migration.
- `test/core/database/v9_app_database.dart` — frozen previous-schema fixture.

## Contracts and interfaces

The presentation facade exposes:

```dart
abstract interface class NotificationSettingsService {
  Stream<NotificationSettingsSnapshot> watch();
  Future<BackgroundMonitoringUpdateResult>
      setBackgroundMonitoringEnabled(bool enabled);
  Future<NewAssignmentNotificationPreferenceUpdateResult>
      setNewAssignmentNotificationsEnabled(bool enabled);
  Future<DeadlineReminderPreferenceUpdateResult>
      setDeadlineRemindersEnabled(bool enabled);
  Future<DeadlineReminderPreferenceUpdateResult> setDeadlineReminderOffset(
    DeadlineReminderOffset offset, {
    required bool enabled,
  });
  Future<DesktopAutostartUpdateResult>
      setDesktopAutostartEnabled(bool enabled);
  Future<NotificationPermissionActionResult>
      requestNotificationPermission();
  Future<TestNotificationActionResult> sendTestNotification();
}
```

The new application-owned preference boundary exposes `watch()` and
`setEnabled(bool)`. Its public results distinguish saved from not-saved without
retaining raw storage errors.

## Data model

Schema v10 adds:

```text
new_assignment_notification_preferences
├── singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1)
└── enabled BOOLEAN NOT NULL DEFAULT true
```

Creation and every supported migration seed singleton ID 1. No credentials,
authorization data, user content, or platform error detail are stored.

Existing tables remain authoritative for:

- `background_schedule_settings.monitoring_enabled`;
- deadline reminder enablement and offsets;
- per-course mute/background policy;
- notification history;
- app/session state.

## State and control flow

### New-assignment disable

1. The preference store starts a Drift transaction and acquires SQLite write
   serialization.
2. Disabling writes `enabled = false`.
3. Every pending or in-flight outbox row becomes terminal
   `new-assignment-disabled` history with its existing stable ID, and the
   outbox is cleared.
4. Every remaining unclaimed, non-baseline discovery receives one canonical
   disabled history row, including retained `seen_activities` whose current
   `activities` row was removed.
5. A concurrent `claimNext` transaction resolves to one canonical history
   outcome, never two.
6. While disabled, claim-time enforcement records the disabled kind and returns
   a consumed claim.
7. Re-enabling consumes anything discovered while disabled before making the
   saved value true, preventing a historical burst.

Suppression needs only the retained seen identity, semester, and first-seen
ordering. Notification history uses that stable identity plus generated local
notification ID and recorded time; it does not require or invent assignment
content when the current activity row is absent.

### Scheduler status freshness

1. The desired monitoring row may emit before native registration completes.
2. The completed update result publishes its authoritative status and
   supersedes an earlier in-flight status read.
3. Session reconciliation requests a fresh status only after native
   reconciliation completes.
4. App resume requests a fresh status after resume synchronization completes.
5. Each request performs one `getStatus()` read and publishes the result to
   active settings streams; there is no timer or busy work.

### Presentation updates

1. A control records its expected saved value and becomes disabled.
2. The owning service persists or updates the OS-backed setting.
3. Failure clears pending state and leaves the visible persisted value intact.
4. Success feedback is shown, but the switch changes only after the local
   stream emits the saved value.
5. Background platform warnings do not reverse already persisted intent.

## Platform behavior

- Android: explicit permission action; best-effort background/reminder copy.
- iOS: explicit permission action; best-effort BG refresh plus launch/resume
  fallback copy.
- macOS: permission and OS-backed start-at-login controls; process-lifetime
  monitoring explanation.
- Linux: start-at-login is available; immediate notifications are supported;
  scheduled deadline notifications are described as unavailable.
- Packaged Windows: start-at-login and scheduled notifications are represented
  as available capabilities.
- Unpackaged Windows: immediate notification remains available while scheduled
  deadline notification limitations are explicit.
- Unsupported targets: notification actions are disabled and no desktop
  autostart row is rendered.

No platform is promised exact execution or delivery.

## Security and privacy

- All settings are local.
- No credential fields were added to SQLite.
- Notification actions carry no credentials or diagnostics.
- Raw Drift, platform, and plugin exceptions never enter widgets.
- Public settings values, services, and results have bounded redacted
  representations.
- Permission is requested only after explanatory copy and explicit user action.

## Decisions

- Keep new-assignment policy in a dedicated checked singleton instead of
  coupling it to session/app settings.
- Default new-assignment notifications on to preserve existing behavior.
- Consume disabled discoveries durably instead of replaying them later.
- Consume retained seen discoveries even when their current activity row is
  absent.
- Enforce global notification policy inside the claim transaction.
- Keep desired monitoring distinct from native scheduling status.
- Refresh actual scheduling state through completion events rather than
  polling or preference-stream side effects.
- Reuse deadline, course, background, autostart, and notification modules
  instead of creating duplicate writers.
- Link to Courses rather than embedding another potentially long course list.
- Use a thin stream aggregate instead of adding `rxdart`.
- Keep permission-action feedback session-local. Passive OS status exists for
  delivery orchestration, but it is not durable application preference state.

## Alternatives rejected

- UI-only notification gating would allow repeated claims and later replay.
- Checking immediately before the platform call would leave claimed work
  ambiguous across disable/re-enable.
- Optimistic switches could display state that was never persisted.
- Treating scheduler `active` as the switch value would overwrite user intent
  with temporary OS state.
- Mirroring start-at-login in SQLite could drift from the operating system.
- Adding more reminder offsets would invent unsupported product behavior.

## Failure behavior

Durable preference failures preserve the previous saved value and produce fixed
copy. Background platform registration failure may accompany a successfully
saved desired value; the switch remains saved while status says unavailable.
Autostart failures make that control unavailable without claiming OS state
changed.

Notification initialization, permission, and test failures map to
`LocalNotificationFailure.message` or one fixed fallback. Settings stream
failure replaces the page with a bounded local-read error and retry action.
Cached assignments and other routes remain unaffected.

## Tests

- Fresh schema v11 default, singleton and outbox constraints, and
  credential-column scan.
- Frozen v9 to v10 migration with prior data preserved.
- Frozen v10 to v11 outbox migration with prior data preserved.
- Existing v1–v8 migrations updated through v11.
- Preference watch/write, disable suppression, disabled-period re-enable, and
  claim/disable race convergence.
- Removed-discovery suppression across disable, re-enable, and stable-identity
  reappearance without duplicate notification/history.
- Claim-time disabled consumption and no replay.
- Application service mapping, failure redaction, stream aggregation, separate
  scheduler status, delayed-registration authoritative status, session-gated
  refresh, delegation, permission-action ordering, and cached-work drain after
  a successful permission grant.
- Root lifecycle status-refresh requests after completed session reconciliation
  and app-resume work.
- Page rendering, no permission on open, pessimistic switch writes, permission
  and test actions, desktop visibility, platform copy, and 200% text reflow at
  320, 375, 600, 768, and 1200 logical pixels.
- Route loading/error/redaction/retry.
- Existing pointer, keyboard, responsive shell, router, diagnostics, database,
  and notification regressions.

## Validation evidence

- Restored checkpoint integrity: 15 of 15 SHA-256 entries passed.
- Focused restored schema/migration/store/claim suite: 24 tests passed.
- Settings/router/adaptive-shell integration: 80 tests passed.
- Complete database/settings/claim suite: 80 tests passed.
- Added claim/disable race regression: 4 tests passed.
- Review-fix focused suites: 13 tests passed.
- `dart format --output=none --set-exit-if-changed .`: 263 files, zero
  changes.
- `dart analyze --fatal-infos`: no issues.
- `flutter analyze --fatal-infos --fatal-warnings`: no issues.
- `flutter test --reporter compact`: all 806 tests passed, including both
  review-fix regressions.
- Code generation was not rerun for the review fixes because no schema,
  generator input, or generated source changed.

- The initial generator attempts exposed a stale/corrupt
  `.dart_tool/build` asset graph. After a scoped build-runner cache clean, the
  repository generation completed in 41 seconds with 513 outputs.
- An immediate second generation pass completed in 1.34 seconds with zero
  outputs. Generated-file SHA-256 values and the worktree file set remained
  unchanged.
- Exact successful sequence, after sourcing `~/.zshrc` once in the new
  terminal:
  `dart run build_runner clean`;
  `timeout --signal=INT --kill-after=5s 75s dart run build_runner build --delete-conflicting-outputs`;
  then the same build with a 30-second timeout for the stability pass.
  Build-runner 2.15.1 warns that the delete flag is removed and ignored; this
  warning did not cause the earlier nonterminal behavior.

## Known limitations

- Android, iOS, macOS, and Windows runtime behavior still requires their native
  hosts. This feature adds no new native implementation.
- OS permission can change outside the app; the page reports only the result
  checked in the current session.
- Background work, reminders, autostart, and desktop process lifetime remain
  subject to the platform limitations documented on the page.

## Future considerations

- Consolidate the three local-notification ID allocator implementations behind
  one tested owner-aware allocator. The standards review accepted this as
  nonblocking debt; it is intentionally outside the two correctness fixes.
- Re-run native settings smoke tests on supported mobile and desktop hosts.

## Related contexts

- [Background Scheduler](background-scheduler.md)
- [Desktop Tray Monitoring](desktop-tray-monitoring.md)
- [Local Notifications](local-notifications.md)
- [New Assignment Notifications](new-assignment-notifications.md)
- [Deadline Reminders](deadline-reminders.md)
- [Course Preferences](course-preferences.md)
- [Local Database](local-database.md)
- [Synchronization Diagnostics](synchronization-diagnostics.md)
