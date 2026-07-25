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

Generate committed Dart sources:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Regenerate continuously while editing annotated sources:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

`build_runner` 2.15.1 accepts these plan-required commands, but reports that
`--delete-conflicting-outputs` has been removed and is ignored. Generated
`*.g.dart` and `*.freezed.dart` files are committed beside their sources; do
not edit them by hand.

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
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed .
dart analyze
flutter analyze
flutter test
flutter build linux
```

Android, iOS, Windows, and macOS builds require their native host toolchains.
