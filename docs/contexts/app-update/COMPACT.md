# App Update

## Status

Implemented. Host tests pass. No release artifact has been published yet, so
the banner has not been observed against a real newer release.

## Purpose

Tell the user that a newer release exists, without a store and without
installing anything on their behalf.

## Scope

- Rendering the `compatibleUpdateAvailable` compatibility state the app
  already computes at launch.
- Per-platform channel resolution.
- A dismissible global banner that opens the published download URL.
- A local notification announcing the release once per version, posted from
  launch and from background runs.

## Non-scope

- A second update-metadata source. There is no GitHub API call; the backend
  `/meta` response is the only source of `latestClientVersion`.
- Downloading or installing artifacts. No APK install intent, no
  `REQUEST_INSTALL_PACKAGES`, no Windows installer or exe replacement.
- Play Store, Microsoft Store, or any store update pipeline.
- Update banners on iOS and macOS; update delivery for those platforms is not
  in development.
- Signing, notarization, and release publishing infrastructure.

## User-visible behavior

When `BackendCompatibilitySnapshot.state` is `compatibleUpdateAvailable`, a
global banner appears above the shell content:

- `download` channel (Android, Windows, non-Flatpak Linux): message plus
  `Open download`, which launches `metadata.downloadUrl` externally, and
  `Later`, which hides the banner for the rest of the process lifetime.
- `flatpak` channel: message telling the user to run `flatpak update` or use
  their software centre, plus `Later`. No download button, because the Flatpak
  sandbox cannot replace read-only `/app`.
- `unmanaged` channel (iOS, macOS): no banner.

Unavailable metadata, an unreadable installed version, and `updateRequired`
all produce no banner here; `updateRequired` routes to `UpdateRequiredPage`
instead. A failed launch rewrites the banner message instead of throwing.

The session-expired banner takes priority over the update banner because the
shell renders one global banner.

Independently of the banner, a notification announces the release:

- Posted at most once per `latestClientVersion` per install, from app launch
  and from background sync runs, so it arrives while the app is closed.
- On the `flatpak` channel the body says to update from the software centre;
  otherwise it says to open the app to download it. The notification has no
  payload, so tapping it only opens the app.
- Background runs read `/meta` at most once per `appUpdateCheckInterval`
  (24 hours), because `latestClientVersion` is deploy-time configuration.
- `unmanaged` channels post nothing, matching the banner.

## Architecture

- `appUpdateBanner(...)` returns the banner widget or `null`, so the shell
  renders no banner padding once the update is dismissed.
- Version comparison and the `compatibleUpdateAvailable` state come from
  `evaluateBackendCompatibility`; nothing is recomputed here.
- `resolveAppUpdateChannel` is pure and takes the operating system name and a
  Flatpak flag; only the Riverpod provider reads `dart:io`.
- Dismissal is a `ValueNotifier<bool>` behind `appUpdateBannerDismissedProvider`,
  not widget `State`: `AdaptiveAppShell` rebuilds the banner from scratch on
  every window-class and text-scale change. Nothing is persisted across
  launches.
- `_SessionAwareShell` subscribes to the compatibility controller and the
  dismissal notifier through one `Listenable.merge`.

The notification is delivered through `AppUpdateNotificationControl`, an
optional capability interface checked with `is` rather than a method on
`LocalNotificationService`: the notice carries no assignment owner, no
schedule, and one fixed replaceable ID
(`localNotificationAppUpdateId`), like the test notification. Announced
versions and the last metadata check live on the `app_settings` singleton
(`notified_update_version`, `update_checked_at_utc`), which is created lazily,
so the store upserts instead of assuming a row.

Recording happens only after the platform accepts the notification, so a
failed write costs a repeated notice rather than a missed one.

The bridge is initialized lazily by whichever coordinator posts first, so a
post begins its own attempt when the service exposes
`LocalNotificationInitializationControl`. Each post bounds that attempt with
`appUpdateNotificationInitializationTimeout`, 30 seconds, and abandons a
timed-out identity-fenced attempt so later notification work can retry.

The background executor reconciles the platform schedule before starting the
optional update check, and skips the check when cancellation latched during
reconciliation. A cancelled active synchronization waits for its ownership to
quiesce and then reconciles without running the optional update check.
Reconciliation is never skipped: a background run is the one place the
registration can move across the daytime/night boundary.

For a non-cancelled result, one budget, `backgroundSyncPostRunBudget`, 90
seconds, covers that whole tail — reconciliation plus metadata, initialization,
notification delivery, and persistence. It exceeds the bounds nested
underneath it, the metadata read's 10-second connect and 30-second receive
timeouts and the bridge's own 30-second initialization timeout, so a slow
network resolves inside the budget and only wedged platform work exceeds it.
Because a Dart timeout does not cancel the underlying future, an overrun returns
the run's result and hands the composition to a close deferred until the tail
settles.

## Important files

- `lib/src/features/app_update/app_update_banner.dart`
- `lib/src/features/app_update/app_update_notifier.dart`
- `lib/src/features/app_update/app_update_notification_store.dart`
- `lib/src/features/background_sync/application/background_sync_task_executor.dart`
  (`BackgroundSyncOwnedComposition.checkForAppUpdate`)
- `lib/src/core/network/backend_compatibility.dart`
  (`compatibleUpdateAvailable`, `BackendApiMetadata`)
- `lib/src/app/design_system/widgets/app_status_banner.dart`
  (`AppStatusBanner.updateAvailable`, optional secondary action)
- `lib/src/app/routing/app_router.dart` (`_SessionAwareShell`)
- `android/app/src/main/AndroidManifest.xml` (`<queries>` VIEW/https, required
  for `launchUrl` on API 30 and above)

## Contracts and interfaces

Backend `/meta`: `latestClientVersion` and `downloadUrl`, already parsed and
validated in `dio_backend_api_client.dart` (absolute `http`/`https`, non-empty
host, no user info). Release versions must match `pubspec.yaml` `version`
semantics, otherwise the metadata is rejected upstream and no banner appears.

## Security and privacy

- No new network call, endpoint, or credential surface: the banner reuses a
  response the app already fetches.
- `downloadUrl` is validated at the parse boundary, so a manipulated payload
  cannot hand the launcher a `file:` or malformed URL.
- No telemetry, no analytics, no persisted update state.

## Failure behavior

Every failure path resolves to "no banner". Notification work never blocks
startup or navigation. A notification initialization that does not settle is
abandoned so a later attempt can retry. A post-run tail that exceeds the
executor's budget is no longer awaited by that caller; composition teardown
waits for it to stop using its owners. Cancellation that latches before update
work starts skips the optional check.

## Tests

`test/features/app_update/app_update_banner_test.dart`: channel resolution,
the null cases (dismissed, unmanaged, current, update-required, unavailable
metadata), download-channel actions and dismissal callback, and the Flatpak
message.

`test/features/app_update/app_update_notifier_test.dart`: one notice per
release, a later release announcing again, silence for current versions and
unmanaged channels, the Flatpak wording, no recording after a failed
notification, the 24-hour background throttle, silence on metadata failure,
lazy bridge initialization before a launch or background post, and abandonment
of a never-settling initialization from both paths.

`test/features/background_sync/application/background_sync_composition_test.dart`:
an over-budget update check timing out at the executor seam after schedule
reconciliation completed, an over-budget reconciliation timing out at the same
seam without the update check starting behind it, composition closure staying
deferred until each settles, cancellation during reconciliation skipping the
optional check, and cancelled active synchronization reconciling after
ownership quiesces and before composition close.

`test/platform/background/ios_background_callback_test.dart`: native expiration
during an update check occurs only after schedule reconciliation and retains
composition ownership until the late check settles.

`test/features/app_update/app_update_notification_store_test.dart` and
`test/core/database/app_update_notification_migration_test.dart`: the lazily
created settings row and the added columns.

## Known limitations

- `latestClientVersion` is backend deploy-time configuration, not a release
  feed. The banner appears only after an operator bumps that field and
  redeploys; publishing a release alone does not trigger it.
- The banner depends on the backend being reachable at launch; an offline
  launch shows nothing until the next launch. `/api/v1/meta` is anonymous, so
  no session or access key is needed for it.
- A Flatpak remote can lag the published version, so the banner may appear
  before `flatpak update` offers the new version.
- Dismissal is not persisted across launches.
- The background notice only arrives while background monitoring is running,
  and no earlier than the next background run after the operator bumps
  `latestClientVersion`; with the 24-hour throttle the worst case is roughly a
  day behind the deploy.
- The notification cannot open the download page directly: it carries no
  payload, so tapping it opens the app and the banner's action.
- Reconciliation, metadata, delivery, and persistence futures have no
  cancellation interface. If one never settles, a timed-out background task
  returns its result but retains one owned composition until the task isolate
  ends, and each later run in that isolate retains another.

## Related contexts

- [Platform Validation](../platform-validation/COMPACT.md)
- [Backend API](../backend/COMPACT.md)
