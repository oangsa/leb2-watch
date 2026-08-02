# LEB2 Watch

LEB2 Watch is a local-first Flutter application that keeps an on-device view
of LEB2 assignments, detects newly published work, and creates local
notifications. It targets Android, iOS, Windows, macOS, and Linux.

> LEB2 Watch is an independent third-party application and is not affiliated with or endorsed by KMUTT or LEB2.

> **Development release 0.5.0:** the host-side function suite and source/static checks
> are green in this checkout: 148 test files passed across 15 sequential
> shards, and Dart and Flutter analysis report no issues. Windows and macOS
> native builds and runtime behavior have not been tested yet, so this beta is
> not a production, store, signing, or notarization readiness claim. No
> release artifact is claimed from this Linux checkout.

## Bring your own backend

LEB2 Watch does not include access to an author-operated backend. To use it,
deploy a compatible
[LEB2SCRAPPER API](https://github.com/oangsa/LEB2SCRAPPER-API) instance and
build the app with that server's HTTPS origin. You control the deployment and
are responsible for its security, availability, quotas, monitoring, and
hosting costs. There is no hosted-service SLA.

This frontend targets the current `dev` contract in the backend repository.
Check the backend's current release or `dev` revision before deployment. See
[Self-hosting the backend](docs/self-hosting-backend.md).

## How it works

```text
                         HTTPS
Flutter application --------------> self-hosted LEB2SCRAPPER API ----> LEB2
       |
       +-- OS secure storage: access key, session cookie, optional sign-in credentials
       +-- local SQLite: cached assignments, settings, and synchronization state
       +-- OS services: local notifications and best-effort background work
```

Cached data renders before network synchronization. The backend uses an
operator-owned Supabase PostgreSQL store for access-key provisioning and local
user/key mapping; sensitive request data and short-lived caches also exist in
its process while requests are handled. Read
[Privacy and security](docs/privacy-and-security.md) before operating a public
server.

The backend operator provisions one access key per user and gives it to that
user out of band. Enter the key at runtime during setup; it is never a
`--dart-define` or part of `AppConfiguration`, and the app stores it only in OS
secure storage.

An access key permanently belongs to one LEB2 account. The backend temporarily
binds that key to one active device. Logging out releases the device binding
without deleting the key or changing its account ownership; cached assignment
data remains on the device. A new device can use the same key only after the
old device logs out or the backend operator resets its binding.

On Android, the app uses the platform `ANDROID_ID` as `X-Device-ID`, so a normal
same-package, same-signing-identity reinstall on the same Android user/profile
can reconnect with the same key after the user re-enters the key and LEB2
credentials. Installing a newer APK over the existing app preserves local
secrets and the binding. Non-Android platforms use a cryptographically random
installation identifier in secure storage; losing that storage may require an
operator reset. The identifier is never shown or logged.

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
| Linux | Application, tray, timers, autostart adapter, secure storage, immediate notifications, process-lifetime deadline reminders | Release build passed; KDE/Wayland Quit and same-instance behavior passed 2/2 in disposable environments, and disposable-HOME autostart entry enable/disable passed; broader desktop integration tests remain |
| Android | Application and WorkManager integration | Sanitized, externally test-signed Release APK built, inspected, installed, and foreground-launched on an API 36 emulator; the explained notification-permission and fixed test-notification submission smoke passed. WorkManager/session/device behavior remains unverified. |
| iOS | Application and BGAppRefresh integration | Dart/static tests only; macOS, Xcode, signing, and device validation required |
| macOS | Application, tray, timer, and autostart | Dart/static tests only; macOS build, signing, and runtime validation required |
| Windows | Unpackaged preview with tray, timers, autostart, immediate and process-lifetime deadline notifications, and same-process tap reveal | Dart/static tests pass and a Windows Release CI gate is configured; native runtime validation is still required |

This is not a store-readiness statement. Signing and packaging remain the
operator's responsibility. See [Platform support](docs/platform-support.md).

## Choose a path

### I want to run LEB2 Watch

1. Deploy the [current backend contract](docs/self-hosting-backend.md).
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
the current backend API reference, .NET 9, Docker, the health response, the
optional Cloud Run example, and production exposure responsibilities.

### I want to contribute

Read [Development](docs/development.md) and
[Contributing](CONTRIBUTING.md). Never use production credentials or submit
session cookies, passwords, assignment data, or raw sensitive logs.

Run the complete host-side unit and widget suite with the checked-in,
memory-safe command:

```bash
dart run tool/run_flutter_tests.dart
```

The mocked Linux device workflow remains a separate integration command.

## Documentation

- [Self-hosting the backend](docs/self-hosting-backend.md)
- [Configuration and builds](docs/configuration-and-builds.md)
- [Architecture](docs/architecture.md)
- [Privacy and security](docs/privacy-and-security.md)
- [Platform support](docs/platform-support.md)
- [Development](docs/development.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Technical feature contexts](docs/contexts/)

## License and security reporting

LEB2 Watch is licensed under [Apache-2.0](LICENSE). See
[SECURITY.md](SECURITY.md) before reporting a security problem: GitHub Issues
are public and are not a channel for confidential information.
