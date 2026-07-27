# Android Local-Notification Runtime Validation

## Status

Completed for the bounded Android local-notification runtime-validation scope.

## Purpose

Provide a bounded native validation path for Android's production local
notification adapter: an explicit permission request and the fixed local-only
test-notification submission.

## Scope

- An opt-in Android integration smoke using `FlutterLocalNotificationsAdapter`
  and `LocalNotificationServiceImpl`.
- One explicit Android notification-permission request and a readback of the
  production delivery-permission status.
- Submission and exact-ID cancellation of the fixed test notification.
- Sanitized Release manifest/build inspection and disposable-emulator commands.

## Non-scope

- Backend, sessions, credentials, secure storage, Drift, assignment data,
  synchronization, WorkManager, deadline scheduling, or production keys.
- Visible-pixel evidence, human notification taps, cold activation, physical
  devices, OEM behavior, or generic Android delivery claims.
- CI enforcement and non-Android platform behavior.

## User-visible behavior

No product behavior changes. This is an explicit developer-only validation
route. The production Settings page remains the user-facing place that explains
and invokes notification permission and test submission.

## Architecture

`integration_test/android_local_notification_runtime_test.dart` constructs the
real plugin, production adapter, and production local-notification service.
It initializes the service, invokes `requestPermission()`, verifies the
delivery toggle, calls `showTestNotification()`, and finally cancels only
`LocalNotificationIdFactory.testNotificationId` through the adapter.

The smoke creates no Riverpod container, database, credential store, backend
client, session, or assignment. The fixed test notification has no payload.

## Important files

- `integration_test/android_local_notification_runtime_test.dart` — opt-in
  production-adapter/service smoke and exact-ID cleanup.
- `lib/src/features/notifications/data/flutter_local_notifications_adapter.dart`
  — Android plugin initialization, permission, status, show, and cancel calls.
- `lib/src/features/notifications/application/local_notification_service_impl.dart`
  — production initialization, permission mapping, and fixed test submission.
- `lib/src/features/notifications/domain/local_notification_id_factory.dart`
  — reserved fixed test notification ID.
- `android/app/src/main/AndroidManifest.xml` — app scheduling receiver policy;
  merged Release output is the authority for plugin-provided notification
  permission declarations.

## Contracts and interfaces

The smoke requires `TargetPlatform.android` and a caller-granted
`POST_NOTIFICATIONS` permission. It intentionally calls the production
permission-request API rather than relying solely on `adb pm grant`; granting
permission beforehand makes this noninteractive check deterministic but does
not prove that a system dialog was rendered or understood.

`showTestNotification()` uses only the application-owned fixed test ID and
fixed local copy. A completing Future proves plugin submission, not visible
rendering, alerting, persistence, accessibility, or user delivery.

## Data model

No persistent application data is created. The only app-level identifier is
the reserved `LocalNotificationIdFactory.testNotificationId`; cleanup calls
`cancel` with that exact value and never `cancelAll`.

## State and control flow

1. The caller starts a disposable API 36 emulator and installs a sanitized,
   externally test-signed Release APK for build/manifest validation.
2. The caller uses the disposable test app state and grants notification
   permission explicitly (manually for dialog observation, or `adb pm grant`
   for deterministic submission validation).
3. The opt-in integration smoke initializes the production adapter/service,
   requests permission, reads the delivery state, and submits the fixed test.
4. `finally` cancels exactly the fixed ID and disposes the service/adapter.
5. A host may query `dumpsys notification` for the known package/channel/ID.
   Only an unambiguous matching record is evidence of notification-manager
   state at that instant; an unavailable or ambiguous query is documented, not
   substituted with a visual or application-level success claim.

## Platform behavior

This validation applies only to the particular API 36 emulator/profile used.
The Android permission request is required on modern Android versions. The
test does not establish device/OEM behavior or terminated-process activation.

## Security and privacy

The test has no backend URL, credentials, session cookie, username, password,
database record, or assignment content. It must use a sanitized backend define
and external non-production signing identity. Do not record keystore paths,
passwords, full notification dumps, or emulator data in repository evidence.

## Decisions

- Reuse the existing fixed test notification instead of adding a synthetic
  assignment payload or changing product code.
- Require pre-granted permission so the command is deterministic and cannot
  falsely report automated system-dialog evidence.
- Keep system-notification-manager inspection an optional bounded evidence
  step because API/image output may not expose a safely identifiable record.

## Alternatives rejected

- Fakes would not exercise Android's plugin implementation.
- `cancelAll` could affect unrelated app-owned notifications.
- UI automation/screenshots would not prove delivery and would broaden the
  feature into visual/tap validation.

## Failure behavior

Initialization, permission, delivery-toggle, or submission failure fails the
smoke. The exact-ID cleanup still runs after a submission failure occurring
after the platform has accepted work. An absent/ambiguous `dumpsys` match is a
missing optional system-record signal, not proof of display or delivery.

## Tests

- `integration_test/android_local_notification_runtime_test.dart` — production
  Android initialization, explicit permission request/readback, fixed test
  submission, and exact-ID cleanup.

## Validation evidence

Run only in the authorized disposable Android environment, after sourcing
`~/.zshrc` once in the terminal before its first Flutter/Dart command:

```bash
# Build/inspect the sanitized external-test-key Release before device use.
flutter build apk --release \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid

# Install the resulting Release for independent startup/build validation.
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Start the smoke. Flutter installs its debug test app itself, so do not grant
# permission before this command has installed it.
flutter test integration_test/android_local_notification_runtime_test.dart \
  -d <emulator-id> --reporter=expanded

# In a second terminal after that app installation, either manually Allow the
# resulting dialog or run this deterministic grant. It does not prove a dialog.
adb shell pm grant dev.oangsa.leb2watch android.permission.POST_NOTIFICATIONS

# A notification-manager query is optional and must inspect only a bounded
# package/channel/ID match while a separately controlled submission is live.
# Do not save full notification dumps.
adb shell dumpsys notification | rg \
  'dev\\.oangsa\\.leb2watch|leb2_assignment_updates_v1|<fixed-test-id>'
```

Observed native evidence on 2026-07-27:

- The sanitized externally test-signed Release APK verified with APK Signature
  Scheme v2, had SHA-256
  `527b5d28dd3a525e005d7c83b6cbcaf545e28e14ebcbc793a6e679589b054103`,
  contained `POST_NOTIFICATIONS` in its merged manifest, installed on the
  API 36 emulator, and launched to `MainActivity`.
- `flutter test integration_test/android_local_notification_runtime_test.dart
  -d emulator-5554 --reporter=expanded` passed 1 test after Flutter installed
  the debug test app and the disposable emulator profile received
  `POST_NOTIFICATIONS`. It exercised the explicit production permission call,
  allowed-status readback, fixed test submission, and exact-ID `finally`
  cleanup.
- `dumpsys notification` did not yield a stable, unambiguous record for the
  short-lived exact-ID notification before cleanup; this feature makes no
  notification-manager-record claim.
- Focused notification/static tests passed 212 tests. The narrower
  configuration/service rerun passed 31 tests. `flutter analyze
  --fatal-infos --fatal-warnings` reported no issues.

Independent final validation completed the separate serial host suite with
durable output: 132 test files, 14 of 14 sequential shards, and 1,097 test
cases passed with `SUITE_EXIT=0`. Repository formatting checked 332 files with
zero changes, and strict Dart and Flutter analysis both reported no issues.
`git diff --check`, untracked-file whitespace checks, and the targeted scan of
the four feature paths for credential/key patterns also passed. The disposable
emulator was force-stopped after exact-ID cleanup.

## Known limitations

The integration test cannot prove that Android displayed a permission dialog,
showed pixels, alerted the user, retained the notification, received a tap,
or cold-launched the app. A test notification manager record, if safely
observable, is limited to OS state at one observation time. It is not a
delivery receipt.

The integration test is intentionally excluded from the host-only serial
runner and remains a separate device command.

## Future considerations

Physical-device and controlled cold-activation validation need a separate
feature with explicit UI/device authority. Fixture-backed sync/outbox and
assignment notification validation remains separate.

## Related contexts

- [Local Notification Service](local-notifications.md)
- [Notification Settings](notification-settings.md)
- [Platform Build Validation](platform-build-validation.md)
