# Changelog

All notable user-visible changes to LEB2 Watch are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Precise daytime fetches need a cadence of 15 min or longer. At 10 min the
  option is shown off and unavailable, and the setting returns when the cadence
  is raised.

## [0.8.0] - 2026-08-09

### Added

- Notification when a new version is released, so the notice arrives while the
  app is closed.
- Optional precise daytime fetches on Android, off by default. Ignores the
  15-minute floor and stops overnight.

### Fixed

- Update notice never posted at all.
- Precise fetches could run past 19:00.
- A stuck notification bridge could hold a background run open.

## [0.7.0] - 2026-08-09

### Added

- Pick the daytime background check cadence: 10, 15, 30, or 60 minutes.
  Overnight stays hourly. Migrates local data to schema 20.

### Changed

- Background checks run on a day/night cadence instead of a fixed 15 minutes.
- A closed app's schedule is now repaired after every background run.

Deadline reminders are unaffected; the operating system holds them in advance.

## [0.6.1] - 2026-08-09

### Fixed

- Reminder flood on the first sync after the backend's activity migration:
  unchanged assignments looked changed.

### Changed

- Settings and assignment-detail layout polish.

## [0.6.0] - 2026-08-08

### Changed

- Deadlines resolve and render in GMT+7, not the device zone. Sort order changes
  for deadlines LEB2 published without an offset.
- Reminders are scheduled against backend time, so a wrong device clock no
  longer shifts them. Migrates local data to schema 18, then 19.

### Fixed

- Alarms already held by the operating system were never corrected when the
  clock offset moved.
- Exact alarm reminders recovered on platforms that had stopped placing them.

## [0.5.1] - 2026-08-05

### Changed

- Signed Android artifacts, and the Linux bundle now runs on distributions that
  ship neither indicator library.

## [0.5.0] - 2026-08-05

Initial development release. Keeps an on-device view of LEB2 assignments,
detects newly published work, and raises local notifications, against a
self-hosted [LEB2SCRAPPER API](https://github.com/oangsa/LEB2SCRAPPER-API)
instance. Linux, Windows, and Android artifacts.

[Unreleased]: https://github.com/oangsa/leb2-watch/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/oangsa/leb2-watch/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/oangsa/leb2-watch/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/oangsa/leb2-watch/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/oangsa/leb2-watch/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/oangsa/leb2-watch/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/oangsa/leb2-watch/releases/tag/v0.5.0
