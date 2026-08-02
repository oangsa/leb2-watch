# Privacy and security

LEB2 Watch is local-first, but using it still sends sensitive authentication
material through an operator-controlled backend to LEB2. Read both the device
and server boundaries before deploying or distributing the app.

## Data kept on the device

| Data | Storage | Notes |
| --- | --- | --- |
| Backend access key | OS secure storage | Per-user secret supplied by the backend operator; sent as `access-key` on every protected `/api/v1` request |
| LEB2 session cookie | OS secure storage | Opaque secret used on protected backend requests |
| Username/password | OS secure storage | Saved only after explicit automatic-reauthentication opt-in |
| Credential schema version | OS secure storage | Version for the optional credential payload |
| Android device identifier | Android platform identity provider | `ANDROID_ID` input sent as `X-Device-ID`; the frontend does not hash or log it |
| Non-Android installation identifier | OS secure storage | Generated once with a cryptographically secure random source; not stored in SQLite or exposed to UI |
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

Android `ANDROID_ID` provides the intended same-device reinstall continuity for
the same Android user/profile and application signing identity. Other platforms
use an installation identity, not a hardware identity claim; losing its secure
storage can require an operator device-binding reset.

Application clearing deletes only LEB2 Watch's three secure entries; it does not
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

- the operator-provided access key in the `access-key` header on protected
  `/api/v1` routes;
- username and password to `/api/v1/User/login` and `/api/v1/User/cookie`;
- the full session cookie in
  `Authorization: Bearer <LEB2-session-cookie>` on protected
  requests; and
- the positive numeric LEB2 user ID in `X-LEB2-USER-ID` on activity requests.

Protected and session-lifecycle requests also send `X-Device-ID`,
`X-Device-Platform`, optional `X-Device-Name` and `X-Device-OS-Version`, and
the semantic installed version in `X-Client-Version`. The anonymous
`GET /api/v1/meta` and `GET /api/v1/health/leb2` requests intentionally send
none of the access, session, device, or client-version headers. The backend
stores only its HMAC of `X-Device-ID`; the frontend does not hash it first.

The backend then communicates with LEB2. Production application builds require
HTTPS, but the operator owns DNS, TLS termination, certificates, renewal, and
the security of every intermediary.

The operator backend uses Supabase PostgreSQL for access-key provisioning,
assignment, local user/key identity mapping (including documented student and
LEB2 identity fields), and audit metadata. It does not store the LEB2 password
or session cookie. Request data and short-lived caches/fingerprints still exist
transiently in the backend process while it handles and coalesces requests.

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

The frontend does not connect directly to Supabase and sends no credentials
other than the documented access key, LEB2 credentials during setup, and opaque
session cookie. It never logs request-header maps, raw device identifiers,
cookies, passwords, or access keys.

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
  access key, saved session, and optional credentials, marks the local session expired, and
  preserves cached assignments.
- **Log out** first calls `/api/v1/User/logout` to release the temporary device
  binding, then clears those secrets while preserving cached account data and
  the local user identity fence. A failed server call does not clear secrets.
- **Delete all local data** attempts to cancel app-owned background work and
  supported notifications, disable desktop autostart, clear credentials,
  logically scrub and then delete SQLite files, remove the app-owned cache, and
  return to onboarding after complete cleanup.

Partial failures are reported as fixed cleanup categories and can be retried.
The UI never displays raw exceptions or paths. These actions remove app-owned
device data only; they do not delete data from LEB2, a hosting provider, proxy
logs, or transient backend memory.

## Reporting security problems

Report non-confidential security problems through the public
[GitHub Issues page](https://github.com/oangsa/leb2-watch/issues/new). GitHub
Issues are public, and this project offers no private security-reporting
channel. Do not put session cookies, passwords, assignment data, personal
identifiers, authorization headers, private keys, private certificates, raw
sensitive logs, or exploit details requiring confidentiality in an issue or
pull request. Redact and minimize proof-of-concept information. See
[SECURITY.md](../SECURITY.md) for the complete reporting policy.

## Licensing boundary

The frontend is licensed under [Apache-2.0](../LICENSE). The backend has its
own [Apache-2.0 license](https://github.com/oangsa/LEB2SCRAPPER-API/blob/dev/LICENSE).
This document does not audit third-party dependency licenses or attribution
requirements.
