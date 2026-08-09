# Changelog

All notable user-visible changes to LEB2 Watch are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Entries describe behavior a user or a self-hosting operator can observe; the
commit history remains the record of implementation detail.

Database schema versions are named where a release migrates local data. A
migration runs once on first launch of the new version and is not reversible by
downgrading.

## [Unreleased]

## [0.8.0] - 2026-08-09

### Added

- New releases are now announced with a local notification, so the notice
  arrives while the app is closed. It is posted at most once per release, from
  app launch and from background synchronization runs; the in-app banner still
  carries the download action. Background runs read release metadata at most
  once a day.
- Optional **precise daytime fetches** on Android (off by default). When
  enabled, new-assignment checks are chained as one-off platform tasks at the
  chosen cadence, which is not subject to the 15-minute periodic floor or the
  platform flex window. The chain is dropped between 19:00 and 06:00, so
  overnight request volume is unchanged, and the hourly periodic request stays
  as the backstop that re-arms the chain after 06:00. It costs battery, and
  only Android both defers this work and can be told to hold an interval.

### Fixed

- The update notice never actually posted: it was the only notification path
  that did not initialize the notification bridge first, so the attempt threw
  and was swallowed — while still arming the 24-hour metadata throttle. Launch
  raced notification startup against the metadata request, and a background run
  only initialized the bridge as a side effect of a committed synchronization,
  so any run that did not reach a successful sync dropped the notice.
- Precise daytime fetches could run after the 19:00 boundary. The last chained
  link landed exactly on 19:00, and the platform treats a one-off delay as an
  eligibility time rather than a deadline, so any link could also be deferred
  past the boundary. A link is now armed only while a whole period still lands
  strictly before 19:00, and the task re-reads the device clock when it is
  dispatched and skips synchronization outside the window.
- A background run could be held open indefinitely by a wedged notification
  bridge while checking for updates. The wait is now bounded at 30 seconds, and
  post-run effects overall are bounded at 90 seconds, after which the
  composition is handed to them and the task returns.

## [0.7.0] - 2026-08-09

### Added

- Selectable daytime cadence for background new-assignment checks — 10, 15, 30,
  or 60 minutes (default 15) — under Settings → Monitoring, so monitoring can be
  made faster or cheaper. The overnight window (19:00–06:00) stays pinned to
  hourly. On Android the copy states the platform's 15-minute minimum for
  periodic work. The control is fixed while background monitoring is off.
- Migrates local data to schema 20 for the persisted cadence.

### Changed

- Background monitoring now runs on a day/night cadence instead of one fixed
  15-minute period, resolved on the device's own clock between 06:00 and 19:00.
  A period that would overshoot the next window boundary is trimmed to it.
- The platform schedule is reconciled after every background run, so a closed
  app's registration can be repaired without opening it.
- A requested cadence below a platform's floor is raised to that floor instead
  of being rejected, so the registered cadence matches the requested one.

This governs new-assignment discovery only. Deadline reminders are pre-scheduled
with the operating system from stored local deadlines, so no cadence choice can
delay them.

## [0.6.1] - 2026-08-09

### Fixed

- A false-positive reminder flood on the first synchronization after the
  backend's v1→v2 activity migration. Cached v1 unzoned deadlines were compared
  as wall-clock strings against their v2 zoned UTC replacements for the same
  instant, so every existing assignment looked changed. Both sides are now
  resolved to their real UTC instant before comparison.

### Changed

- Settings and assignment-detail layout polish: destructive actions are
  emphasized, the local-data panel is softened, the duplicate course link is
  gone, and the detail layout is simplified.
- Android build targets added to the build tooling.

## [0.6.0] - 2026-08-08

### Changed

- **Deadlines now resolve and render in the app time zone (GMT+7), not the
  device zone.** LEB2 publishes deadlines without a UTC offset, and anything
  that parsed those read them in the device zone — so a device outside GMT+7
  filtered, sorted, and scheduled every offset-less deadline against the wrong
  instant. Notification copy renders in the same zone with a GMT+7 label. The
  dashboard's separate unzoned-deadline sort group is gone, so ordering changes
  for any assignment LEB2 published without an offset.
- **Deadline reminders are scheduled against backend time, not the device
  clock.** A wrongly set device clock shifted every reminder by the same error,
  silently. The offset is measured against the `Date` header of responses the
  app already makes, at the round-trip midpoint, and applied when the alarm is
  handed to the operating system. Readings past a 5-second round trip or a
  12-hour skew are discarded, and a reading served from a cache (positive `Age`)
  is ignored.
- Migrates local data to schema 18, then 19, to persist the clock correction
  each operating-system alarm was placed under.

### Fixed

- Alarms already held by the operating system were never corrected when the
  clock offset moved, including every alarm placed before the first
  measurement of a launch. Correction movement is now recorded per reminder
  rather than per reconciliation, and reminders in flight to the platform are
  swept as well, so a device clock repaired while the app was closed re-places
  the affected alarms instead of leaving them permanently wrong.
- Exact alarm reminders recovered on platforms that had stopped placing them.

## [0.5.1] - 2026-08-05

### Changed

- Tagged releases now build signed Android artifacts and bundle the tray
  libraries into the Linux bundle, so the Linux build runs on distributions
  that ship neither indicator library.

## [0.5.0] - 2026-08-05

Initial development release. A local-first Flutter application that keeps an
on-device view of LEB2 assignments, detects newly published work, and raises
local notifications, against a self-hosted
[LEB2SCRAPPER API](https://github.com/oangsa/LEB2SCRAPPER-API) instance.

Includes cached-first assignment browsing, background new-assignment
monitoring, deadline reminders pre-scheduled with the operating system, secure
storage of the access key and session, and desktop tray, autostart, and window
behavior. Linux, Windows, and Android artifacts are produced by the tagged
release workflow; see the README for what is verified on each platform.

[Unreleased]: https://github.com/oangsa/leb2-watch/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/oangsa/leb2-watch/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/oangsa/leb2-watch/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/oangsa/leb2-watch/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/oangsa/leb2-watch/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/oangsa/leb2-watch/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/oangsa/leb2-watch/releases/tag/v0.5.0
