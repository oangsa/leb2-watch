# Privacy and security

LEB2 Watch is local-first, but using it still sends sensitive authentication
material through an operator-controlled backend to LEB2. Read both the device
and server boundaries before deploying or distributing the app.

## Data kept on the device

| Data | Storage | Notes |
| --- | --- | --- |
| LEB2 session cookie | OS secure storage | Opaque secret used on protected backend requests |
| Username/password | OS secure storage | Saved only after explicit automatic-reauthentication opt-in |
| Credential schema version | OS secure storage | Version for the optional credential payload |
| Assignment snapshots and course data | Local SQLite | Cached for immediate/offline display |
| Settings and session lifecycle | Local SQLite | Non-secret app coordination state |
| Seen identities, fingerprints, sync history/backoff | Local SQLite | Bounded local synchronization state |
| Notification history, retryable outbox, and reminder ownership | Local SQLite | Provides app-level deduplication and submission state, not proof of OS delivery |

Credentials do not belong in SQLite, `SharedPreferences`, plaintext files,
logs, notification payloads, diagnostics, or crash reports.

The app has no analytics, advertising, remote user-data persistence,
push-token registration, or remote crash-reporting dependency.

## Secure storage by platform

- **Android:** plugin-owned encrypted preferences use an app-specific
  namespace. App backup is disabled, and the secure-storage files are excluded
  from legacy backup, cloud backup, and device transfer.
- **iOS:** the app uses its Keychain service with
  `first_unlock_this_device` accessibility and no synchronization.
- **macOS:** the same app-owned service uses the data-protection Keychain and
  no synchronization.
- **Windows:** the secure-storage plugin uses its DPAPI-backed default.
- **Linux:** the libsecret adapter requires an available, unlocked Secret
  Service keyring.

Application clearing deletes only LEB2 Watch's two secure entries; it does not
call a keyring-wide `deleteAll`.

## Automatic reauthentication

Username/password persistence is optional and off by default. When enabled,
the application permits one automatic attempt for the exact expired-session
revision. It obtains and verifies a candidate cookie before replacing the
saved cookie; a failed candidate is not persisted.

Foreground session replacement, automatic recovery, credential deletion, and
delete-all share lifecycle and mutation fencing. If credentials are deleted
while a candidate is in flight, that late candidate cannot restore the cookie,
username/password, or durable reauthentication state. Failure safely leaves
cached assignments available and falls back to the manual reconnect flow.

## What is sent to the backend

Depending on the setup path, the app sends:

- username and password to `/User/login` and `/User/cookie`;
- the full session cookie in
  `Authorization: Bearer <LEB2-session-cookie>` on protected
  requests; and
- the positive numeric LEB2 user ID in `X-LEB2-USER-ID` on activity requests.

The backend then communicates with LEB2. Production application builds require
HTTPS, but the operator owns DNS, TLS termination, certificates, renewal, and
the security of every intermediary.

The backend has no durable per-user database or credential persistence, but
request data and short-lived caches/fingerprints exist transiently in the
backend process while it handles and coalesces requests.

Default backend memory caches retain structure results for about 60 seconds and
activity results for about 30 seconds. Cache, throttle, health, backoff, and
correlation state are process-local. See
[Self-hosting the backend](self-hosting-backend.md).

## Logging and intermediaries

Request-scoped handling in the backend cannot prevent a reverse proxy, hosting
provider, APM agent, or operator-added logger from recording sensitive
headers or bodies.

Operators must:

- disable Authorization, cookie, credential, and request-body logging;
- review provider and proxy access logs;
- keep optional SMTP credentials in provider secret storage;
- apply least privilege to deployment identities;
- protect build signing keys;
- patch the app, backend, runtime, browser, and host;
- review public exposure, permissive CORS, and `AllowedHosts: *`;
- configure cost controls, quotas, alerts, and retention; and
- test deletion and session-expiration behavior with sanitized data.

The current frontend cannot send an extra API key, Basic-auth credential,
Cloud Run IAM identity token, or generic proxy-authentication header. Requiring
one needs a corresponding frontend contract change.

## Local notifications and diagnostics

Notifications contain bounded course/title/deadline display copy and a
versioned local assignment identifier. They contain no cookie, username,
password, authorization header, or raw backend data.

Diagnostics expose fixed failure categories, counts, timestamps, scheduler
state, and session state. They do not display raw stack traces, response
bodies, headers, cookies, passwords, or user IDs.

Operating systems may still show notification content on a lock screen.
Users should apply the device notification-privacy settings appropriate to
their needs.

## Delete local data

Settings provides three confirmed actions:

- **Delete cached assignments** removes the semester-owned local graph,
  including assignment identities, course data, reminder ownership,
  notification history, and synchronization history. Credentials and global
  preferences remain.
- **Delete saved credentials** stops app-owned periodic scheduling, clears the
  saved session and optional credentials, marks the local session expired, and
  preserves cached assignments.
- **Delete all local data** attempts to cancel app-owned background work and
  supported notifications, disable desktop autostart, clear credentials,
  logically scrub and then delete SQLite files, remove the app-owned cache, and
  return to onboarding after complete cleanup.

Partial failures are reported as fixed cleanup categories and can be retried.
The UI never displays raw exceptions or paths. These actions remove app-owned
device data only; they do not delete data from LEB2, a hosting provider, proxy
logs, or transient backend memory.

## Reporting security problems

The project does not yet designate a private security-reporting address or
enable a documented private vulnerability-reporting mechanism. That is a
release blocker.

Until one is published, do not put session cookies, passwords, assignment data,
personal identifiers, authorization headers, private certificates, or raw
sensitive logs in a public issue or pull request. Repository visibility is not
permission to disclose another user's data.

## Licensing boundary

Both the frontend and backend are publicly visible but currently have no
license. They are source-available, not legally open source, until the owner
chooses and commits licenses. Do not infer permission to deploy, modify, or
redistribute from public visibility alone.
