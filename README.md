# LEB2 Watch

Local-first assignment monitoring for LEB2.

## Requirements

- Flutter 3.44.8 stable
- Dart 3.12.2

## Run

Install dependencies:

```bash
flutter pub get
```

Run with compile-time development configuration:

```bash
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=<BACKEND_BASE_URL>
```

Use `APP_ENV=production` for a production build. The application supports only
`development` and `production`; the backend URL is intentionally not committed
to the repository.

## Validate

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build linux
```

Android, iOS, Windows, and macOS builds require their native host toolchains.
