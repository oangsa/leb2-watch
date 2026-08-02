# Architecture

LEB2 Watch is local-first: the interface reads durable device state first,
then synchronization updates that state asynchronously. The backend is a
transport/scraping boundary plus an operator-owned Supabase PostgreSQL store
for access-key provisioning and local user/key identity mapping. It can retain
short-lived process-local cache, throttle, backoff, health, and correlation
state; none of that is the application's database.

## Data flow

```text
Flutter UI and Riverpod state
             |
             v
Application services and domain interfaces
       |                         |
       v                         v
Drift / secure storage     platform adapters
       |                   notifications, background,
       |                   tray, window, autostart
       |
       +---- cached state

Synchronization service -> Dio transport -> self-hosted backend -> LEB2
                                |
                                +-- verified transport models
                                      |
                                      v
                                  domain values
```

Widgets do not depend on Dio, Drift, or native plugin types. Application-owned
interfaces isolate transport, persistence, secure credentials, notifications,
background scheduling, and desktop behavior.

## Startup and cached rendering

Production bootstrap resolves the initial application-flow stage from local
evidence before attaching the first product frame. It reads only the
app-settings/session lifecycle, active-semester selection, and whether all
required secure session values (access key and session cookie) are present. It
then performs a best-effort anonymous `GET /api/v1/meta` compatibility check.
The metadata check never replaces the local-first state or clears local data,
and it reuses the same database and credential boundaries when it constructs
the Riverpod graph.

A proven prior session and selected semester can therefore open the dashboard
directly, where Drift emits cached assignments before asynchronous
synchronization completes. Missing or inconsistent local proof resolves
conservatively to onboarding, authentication, or semester selection. Exact
session expiration can still resolve to the dashboard so cached assignments
remain visible.

The integration suite verifies close/reopen persistence by removing one
widget/provider graph, closing its database manager, reopening the same SQLite
file, and constructing a new graph while a backend response is gated. This is
an application-lifetime restart inside one Linux test executable, not a
separate operating-system process relaunch.

Bootstrap maps three startup failure categories to fixed, redacted recovery
surfaces: invalid `APP_ENV`, local-data initialization failure, and application
integration failure. It performs no same-process retry and does not delete
saved data. `BACKEND_BASE_URL` is different: validation is lazy when a network
capability is resolved. Cached semester and assignment views can be
constructed without Dio, while authentication and synchronization require a
valid configured URL.

## Main layers

| Area | Responsibility |
| --- | --- |
| `lib/src/app` | Bootstrap composition, routing, adaptive shell, lifecycle integration |
| `lib/src/core` | Configuration, database, network, session, security, and shared domain boundaries |
| `lib/src/features` | Onboarding, authentication, semesters, assignments, notifications, background sync, settings, and diagnostics |
| `lib/src/platform` | Android/iOS background adapters and desktop tray/window/autostart adapters |

Riverpod owns application composition and lifecycle. `go_router` owns named
routes and adaptive navigation. Freezed domain values remain separate from
JSON transport models.

## Storage ownership

| Data | Owner | Persistence |
| --- | --- | --- |
| Backend access key | Credential store | OS secure storage |
| Session cookie | Credential store | OS secure storage |
| Optional username/password | Credential store, only after explicit automatic-reauthentication opt-in | OS secure storage |
| Non-Android installation identity | Runtime device provider | OS secure storage; generated once and never stored in SQLite |
| Android device identity | Runtime device provider | Platform `ANDROID_ID`; not logged, stored, or hashed by the frontend |
| Installed semantic app version | Package metadata provider | Runtime metadata, not hardcoded in transport |
| Semesters, courses, activities | Assignment database | Local SQLite |
| Seen identities and fingerprints | Synchronization/diff engine | Local SQLite |
| Notification/reminder ownership and history | Notification application layer | Local SQLite |
| Preferences, session lifecycle, diagnostics, backoff | Feature stores | Local SQLite |
| Backend access-key provisioning and user/key mapping | Operator backend | Supabase PostgreSQL |
| Backend request/cache state | Self-hosted backend | Request scope and short-lived process memory |

Credentials are deliberately absent from SQLite. The application has no direct
Supabase connection, analytics, advertising, push-token registration, or remote
crash reporting.

## Device binding, compatibility, and logout

The transport resolves one runtime identity representation for foreground,
session-setup, automatic reauthentication, and headless background requests.
Protected `/api/v1` calls send `X-Device-ID`, `X-Device-Platform`, optional
device metadata, and `X-Client-Version`; anonymous `/api/v1/meta` sends none of
those headers. The backend stores only an HMAC of the device identifier.

`426 CLIENT_UPDATE_REQUIRED` and an incompatible `/api/v1/meta` result are
non-retryable application compatibility failures. They reach one global
blocking update route; the route opens the backend-provided download URL in an
external browser and never downloads or installs an APK itself.

Logout is server-first: `/api/v1/User/logout` must return `204 No Content`
before access key, cookie, and optional credentials are cleared. Cache,
preferences, notification history, and the local user identity remain. The
existing background scheduler is cancelled/reconciled after successful local
credential cleanup. Network or device-mismatch failure leaves secrets intact.

## Synchronization flow

Every trigger uses the same `AssignmentSyncService`: setup, launch, resume,
manual refresh, mobile background work, desktop timer, and tray action.

1. Read session, selected semester, monitoring policy, and backoff state.
2. Join an existing same-target operation instead of issuing a duplicate HTTP
   request.
3. Fetch a verified nested snapshot outside the database transaction.
4. Validate and map transport data into domain values.
5. Reconcile the snapshot, identities, change evidence, history, and retry
   state in a transaction.
6. Complete the operation only after the transaction commits.
7. Claim notification and deadline-reminder effects from committed evidence.
8. Call supported local OS services.

Malformed or failed responses never replace a valid local snapshot. A
first/baseline synchronization stores historical assignments without producing
new-assignment notifications. Later snapshots use stable backend IDs and
versioned deterministic ownership to prevent duplicate effects.

The synchronization lock is durable SQLite coordination with fenced ownership
and leases, rather than a UI-isolate mutex. The UI and background entry points
therefore share one local source of truth.

## Notifications

Local notification requests contain bounded display copy and versioned local
assignment targets. They contain no credentials or raw backend response.

New-assignment delivery uses a durable retryable outbox and a shared
collision-aware stable-ID allocator also used by deadline reminders and
settings suppression. Ownership is persisted before platform I/O. A plugin
result records app-level submission, not proof that the operating system
delivered or displayed the notification. Unsupported
scheduling/cancellation is represented explicitly, especially on Linux and
unpackaged Windows.

## Background families

One scheduler contract is implemented by:

- Android WorkManager unique periodic work;
- iOS BGAppRefresh through Workmanager;
- a non-overlapping, process-local desktop timer; and
- an explicit unsupported adapter on other families.

Global monitoring defaults off. Mobile scheduling is system-controlled and
desktop scheduling requires the application process to remain alive. All
families run the shared synchronization service and its local target, session,
course, and backoff gates.

Desktop composition also owns tray actions, close-to-tray explanation,
single-instance behavior, and opt-in start at login. It does not install a
service or daemon.

## Session expiration and failures

Only the verified combination of HTTP 401 and `SESSION_EXPIRED` expires the
saved session. Timeouts, HTML responses, malformed JSON, and unrelated 401
errors remain distinct failures.

Expiration:

- pauses automatic synchronization;
- preserves cached assignments and settings;
- shows reauthentication guidance; and
- resumes normal monitoring only after a replacement session verifies and
  persists.

If the user explicitly opted in to saving username/password, automatic
reauthentication permits one attempt for the exact expired-session revision.
It obtains and verifies a candidate cookie before secure save, uses shared
lifecycle/mutation fencing so manual replacement or deletion wins safely, and
runs at most one non-recursive direct synchronization continuation. Failure or
attempt exhaustion leaves cached data visible and falls back to manual
authentication.

Retry policy distinguishes temporary network/backend failures from
non-retryable authentication and response failures. `Retry-After` is retained
where available.

## Local deletion

The deletion coordinator provides three bounded operations:

- delete cached assignments;
- delete saved credentials; and
- delete all local data.

Delete-all cancels app-owned background scheduling and supported notifications,
clears the two secure credential entries, logically scrubs SQLite, proves
database quiescence before deleting the database and sidecars, removes only the
app-owned cache directory, resets providers, and returns to onboarding after a
complete result. It never claims to delete data from LEB2 or a backend.

## Technical references

- [Verified backend contract](contexts/backend/COMPACT.md#contracts-and-interfaces)
- [Local database](contexts/database/COMPACT.md#data-model)
- [Secure credential storage](contexts/session/COMPACT.md#contracts-and-interfaces)
- [Assignment synchronization](contexts/assignments/COMPACT.md#architecture)
- [Assignment diffing](contexts/assignments/COMPACT.md#contracts-and-interfaces)
- [Local notifications](contexts/notifications/COMPACT.md#architecture)
- [Background scheduler](contexts/infrastructure/COMPACT.md#architecture)
- [Local data deletion](contexts/deletion/COMPACT.md#state-and-control-flow)
- [Frontend integration testing](contexts/repository/COMPACT.md#validation-evidence)
- [Platform build validation](contexts/platform-validation/COMPACT.md#validation-evidence)
