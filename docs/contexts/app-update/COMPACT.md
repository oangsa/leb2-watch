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

## Important files

- `lib/src/features/app_update/app_update_banner.dart`
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

Every failure path resolves to "no banner". The check never blocks startup,
navigation, or synchronization.

## Tests

`test/features/app_update/app_update_banner_test.dart`: channel resolution,
the null cases (dismissed, unmanaged, current, update-required, unavailable
metadata), download-channel actions and dismissal callback, and the Flatpak
message.

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

## Related contexts

- [Platform Validation](../platform-validation/COMPACT.md)
- [Backend API](../backend/COMPACT.md)
