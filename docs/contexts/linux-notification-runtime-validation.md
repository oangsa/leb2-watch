# KDE Linux Local-Notification Runtime Validation

## Status

Completed on the current interactive KDE Plasma/Wayland host. This is an
opt-in native evidence gate, not a portable CI test.

## Purpose

Prove that LEB2 Watch's production Linux notification path can submit one
synthetic assignment notification to the live KDE server and decode a
same-process default action into the exact local assignment target.

## Scope

- One Linux-device-only integration smoke using the production Flutter adapter
  and local notification service.
- KDE/Plasma server, action capability, and `InvokeAction` preflight checks.
- App-ID-to-server-ID lookup, bounded response wait, exact decoded target,
  and cleanup of one known notification ID.

## Non-scope

- Backend, credentials, database, secure storage, scheduling, reminders,
  cold activation, DBus activation, screenshots, generic Linux portability,
  Windows, macOS, Android, or CI enforcement.

## User-visible behavior

No product behavior changed. A developer can run the opt-in smoke from an
interactive KDE desktop. It submits a synthetic notification that may be
visible, then removes only that notification before the test exits.

## Architecture

`integration_test/linux_local_notification_runtime_test.dart` constructs a
real `FlutterLocalNotificationsPlugin`, injects it into
`FlutterLocalNotificationsAdapter`, and constructs
`LocalNotificationServiceImpl`. It does not use a fake platform. After the
service encodes and submits a synthetic `NewAssignmentNotification`, the test
reads the public Linux plugin system-ID map and calls KDE's server-owned
`org.kde.NotificationManager.InvokeAction` for `default`. The service response
stream must emit the exact `AssignmentNotificationTarget`.

## Important files

- `integration_test/linux_local_notification_runtime_test.dart` — opt-in KDE
  submission/action smoke and exact-ID cleanup.
- `lib/src/features/notifications/data/flutter_local_notifications_adapter.dart`
  — production plugin boundary used by the smoke.
- `lib/src/features/notifications/application/local_notification_service_impl.dart`
  — production payload validation and response publication used by the smoke.
- `docs/contexts/local-notifications.md` — service-wide capability and limit
  record.

## Contracts and interfaces

The test requires `TargetPlatform.linux`, `gdbus`, a freedesktop notification
server identifying as KDE Plasma, the `actions` capability, and KDE's
`InvokeAction` endpoint. It uses `LinuxFlutterLocalNotificationsPlugin`
`getSystemIdMap()` only to find its own app notification ID.

## Data model

The test uses only synthetic constants: semester `1`, `backend:1`, course
`1`, and non-reserved notification ID `2147483645`. It creates no persistent
application database data and supplies no credentials or backend URL.

## State and control flow

1. Preflight verifies the target platform and live KDE action endpoint.
2. The service initializes and subscribes to responses before submission.
3. The service submits the synthetic new-assignment notification.
4. The Linux plugin returns the KDE system ID for the exact app ID.
5. KDE invokes `default`; the test awaits one exact decoded target.
6. `finally` cancels only the known app ID, then disposes the stream/service.

## Platform behavior

This evidence applies only to the current KDE Plasma/Wayland session. The
KDE-specific action endpoint is not a freedesktop cross-desktop contract.
Xvfb CI is intentionally unchanged because it does not provide this server.

## Security and privacy

No backend request, credential, assignment record, SQLite data, or secure
storage is used. Test content is synthetic. The test never calls `cancelAll`
or deletes the plugin's shared XDG runtime cache.

## Decisions

- Keep cleanup at the existing adapter `cancel(id)` seam instead of adding a
  broad product API solely for a test.
- Use a fixed valid ID outside the reserved test ID so cleanup is exact and
  auditable.
- Treat KDE server acceptance and action callback as distinct from visual or
  human delivery evidence.

## Alternatives rejected

- A recording/fake notification platform would not exercise the Linux plugin
  or session D-Bus.
- `cancelAll` or runtime-cache deletion could remove live application state.
- Screen capture/click automation risks unrelated desktop content and would
  still not prove portable behavior.
- Adding the smoke to generic Linux CI would falsely require KDE services.

## Failure behavior

Missing KDE prerequisites, no server ID, nonzero `gdbus`, or no callback within
ten seconds fails with an actionable redacted error. If submission began, the
`finally` block attempts cancellation of the exact known ID even after a later
assertion or timeout.

## Tests

- Native KDE smoke: production submission, server-ID mapping, default action,
  strict target decoding, and exact-ID cleanup.
- Existing notification service/adapter/native-configuration tests remain the
  focused regression coverage for application behavior and platform policy.

## Validation evidence

After sourcing `~/.zshrc` before the terminal's first Flutter command:

```text
flutter test integration_test/linux_local_notification_runtime_test.dart \
  -d linux --reporter=expanded
Built build/linux/x64/debug/bundle/leb2-watch
1 passed
```

The successful test is runtime evidence that the production path reached the
current KDE server and received its same-process `default` action callback.

## Known limitations

This does not prove that a notification was visibly rendered, that a human
clicked it, that a cold or terminated process can receive an action, that
deadline schedules survive process exit, or that other Linux desktops behave
the same way.

## Future considerations

Run equivalent explicit native checks on supported non-Linux platforms. Any
future cold activation work must preserve the existing local payload and
privacy boundaries.

## Related contexts

- [Local Notification Service](local-notifications.md)
- [New-Assignment Notifications](new-assignment-notifications.md)
- [Platform Build Validation](platform-build-validation.md)
