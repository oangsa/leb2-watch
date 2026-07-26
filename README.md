# LEB2 Watch

LEB2 Watch is a local-first Flutter application that keeps an on-device view
of LEB2 assignments, detects newly published work, and creates local
notifications. It targets Android, iOS, Windows, macOS, and Linux.

> LEB2 Watch is an independent third-party application and is not affiliated with or endorsed by KMUTT or LEB2.

## Bring your own backend

> **License notice:** No license is currently committed. These instructions are
> documentation only; deployment or reuse requires separate permission from the
> repository owner.

LEB2 Watch does not include access to an author-operated backend. To use it,
deploy a compatible
[LEB2SCRAPPER API](https://github.com/oangsa/LEB2SCRAPPER-API) instance and
build the app with that server's HTTPS origin. You control the deployment and
are responsible for its security, availability, quotas, monitoring, and
hosting costs. There is no hosted-service SLA.

The backend default branch is not currently compatible with this frontend.
Self-hosters must use backend commit
`d6e3261537c53507873f36de166f6245bc82fcc4` until a compatible release is
published. See [Self-hosting the backend](docs/self-hosting-backend.md).

## How it works

```text
                         HTTPS
Flutter application --------------> self-hosted LEB2SCRAPPER API ----> LEB2
       |
       +-- OS secure storage: session cookie and optional sign-in credentials
       +-- local SQLite: cached assignments, settings, and synchronization state
       +-- OS services: local notifications and best-effort background work
```

Cached data renders before network synchronization. The backend has no durable
per-user database, but sensitive request data and short-lived caches exist in
its process while requests are handled. Read
[Privacy and security](docs/privacy-and-security.md) before operating a public
server.

## Current capabilities

- Privacy-first onboarding and verified session setup.
- Cached semester, course, assignment dashboard, and assignment detail views.
- Single-flight synchronization with baseline/diff detection and retry
  backoff.
- Durable new-assignment deduplication/outbox submission and reconciled
  deadline reminders, without claiming exact operating-system delivery.
- Process-lifetime deadline reminder delivery on Linux and the unpackaged
  Windows preview.
- Local notification, course, monitoring, and reminder preferences.
- Session-expiration recovery that retains cached assignments, with optional
  opt-in automatic reauthentication and safe manual fallback.
- Android/iOS best-effort background refresh and desktop tray monitoring.
- Local synchronization diagnostics and complete on-device data deletion.

Background checks and notification delivery are always best effort. Mobile
operating systems may delay or omit work, and desktop monitoring stops when the
process exits.

## Platform status

| Platform | Implementation | Validation on the current Linux host |
| --- | --- | --- |
| Linux | Application, tray, timers, autostart adapter, secure storage, immediate notifications, process-lifetime deadline reminders | Release build passed; live desktop integrations still need environment-specific smoke tests |
| Android | Application and WorkManager integration | Dart/static tests only; Android SDK and device validation unavailable |
| iOS | Application and BGAppRefresh integration | Dart/static tests only; macOS, Xcode, signing, and device validation required |
| macOS | Application, tray, timer, and autostart | Dart/static tests only; macOS build, signing, and runtime validation required |
| Windows | Unpackaged preview with tray, timers, autostart, immediate and process-lifetime deadline notifications, and same-process tap reveal | Dart/static tests pass and a Windows Release CI gate is configured; native runtime validation is still required |

This is not a store-readiness statement. Signing and packaging remain the
operator's responsibility. See [Platform support](docs/platform-support.md).

## Choose a path

### I want to run LEB2 Watch

1. Deploy the [compatible backend](docs/self-hosting-backend.md).
2. Install Flutter `3.44.8` with Dart `3.12.2`.
3. Install dependencies and generate committed sources:

   ```bash
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```

4. Run against a backend reachable from the selected device:

   ```bash
   flutter run -d <DEVICE_ID> \
     --dart-define=APP_ENV=development \
     --dart-define=BACKEND_BASE_URL=http://<REACHABLE_HOST>:5015
   ```

`BACKEND_BASE_URL` is embedded at build time. Production requires an HTTPS
root origin, and changing servers requires rebuilding the app. Read
[Configuration and builds](docs/configuration-and-builds.md) before producing
a release.

### I need to host the backend

Start with [Self-hosting the backend](docs/self-hosting-backend.md). It covers
the pinned compatible revision, .NET 9, Docker, the health response, the
optional Cloud Run example, and production exposure responsibilities.

### I want to contribute

Read [Development](docs/development.md) and
[Contributing](CONTRIBUTING.md). Never use production credentials or submit
session cookies, passwords, assignment data, or raw sensitive logs.

## Documentation

- [Self-hosting the backend](docs/self-hosting-backend.md)
- [Configuration and builds](docs/configuration-and-builds.md)
- [Architecture](docs/architecture.md)
- [Privacy and security](docs/privacy-and-security.md)
- [Platform support](docs/platform-support.md)
- [Development](docs/development.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Technical feature contexts](docs/contexts/)

## Source availability and licensing

The frontend and backend repositories are publicly visible but do not
currently include a license. Until the owner chooses and commits licenses,
they are source-available, not legally open source, and no general permission
to use, modify, or redistribute should be assumed. License selection for both
repositories is a release blocker.
