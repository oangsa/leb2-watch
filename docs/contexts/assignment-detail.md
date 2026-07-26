# Assignment Detail

## Status

Completed for Feature 11.2. The implementation is local-only and adds no
schema or backend request.

## Purpose

Let a user open one saved assignment from the dashboard and inspect the
verified cached record without waiting for the backend or exposing untrusted
HTML. The view remains truthful when only historical observation evidence
survives.

## Scope

- A validated semester-scoped assignment detail key and named local route.
- Current, seen-only, and missing local states.
- One coherent Drift read over current content and local evidence.
- Presentation-safe HTML-fragment-to-plain-text conversion.
- Verified title, course, description, activity type, deadline, source-created
  time, and backend-reported deadline-exceeded status.
- Aggregate course-mute, reminder, notification-history, observation, and
  retained synchronization evidence.
- Responsive Record Sheet presentation and dashboard row activation.

## Non-scope

- Backend fetching or synchronization triggers.
- Attachment or external-link decoding and activation.
- Publication, completion, cancellation, or remote-deletion claims.
- Notification display, delivery, permission, or scheduling side effects.
- Global notification settings.
- Database schema or migration changes.
- A dashboard/detail master-pane redesign.

## User-visible behavior

A compact or expanded dashboard row opens
`/assignments/:semesterId/:identityKey` inside the adaptive shell. Current
assignments show a factual record and sanitized selectable description.
The local-notification service uses the same validated key and named route;
supported notification targets wait through incomplete app-flow gates and
retain their explicit semester.

A seen-only assignment says that it no longer appears in the latest saved
snapshot and does not retain a removed title or description. A missing
assignment says it is not saved on this device. A later local-read failure
keeps the last rendered record visible with a stale-local-data banner.

Zoned source timestamps render in device local time. Unzoned source timestamps
retain their wall-clock source and say that the timezone was not provided.
`createdAt` is labelled “Source-created time” and explicitly is not presented
as publication time.

## Architecture

`AssignmentDetailKey` is the route and storage identity boundary.
`DriftAssignmentDetailStore` watches the seven owning tables and resolves each
invalidation inside one read transaction. Raw HTML exists only in the data
layer's current-state value.

`LocalNotificationPayloadCodec` reconstructs notification targets only through
`AssignmentDetailKey.tryParse`. `NotificationNavigationCoordinator` holds the
newest validated target outside `GoRouter` until the app flow is ready.

`LocalAssignmentDetailService` is the security seam: it sanitizes the
description, classifies timestamps without assigning a timezone, maps raw
storage values to presentation-owned states, and bounds exceptions.

`AssignmentDetailPage` owns the local stream subscription and preserves its
last state on a later stream error. `AssignmentDetailRoute` validates path
parameters before watching a provider and composes loading/error/retry
surfaces. The dashboard sends only the validated key through `pushNamed`.

## Important files

- `lib/src/features/assignments/detail/domain/assignment_detail_key.dart` —
  strict semester and identity validation.
- `lib/src/features/assignments/detail/data/assignment_detail_store.dart` —
  coherent local read and storage-only models.
- `lib/src/features/assignments/detail/application/assignment_description_sanitizer.dart`
  — HTML-fragment-to-inert-text conversion.
- `lib/src/features/assignments/detail/application/assignment_detail_service.dart`
  — presentation-safe states and timestamp/evidence mapping.
- `lib/src/features/assignments/detail/presentation/assignment_detail_page.dart`
  — responsive Record Sheet UI.
- `lib/src/features/assignments/detail/presentation/assignment_detail_route.dart`
  — path validation and provider composition.
- `test/features/assignments/detail/` — domain, sanitizer, store, service, page,
  and route tests.

## Contracts and interfaces

The local route is:

```text
/assignments/:semesterId/:identityKey
```

The semester must be a positive int32. The identity is exactly
`backend:<positive-int32>` or `fingerprint:v1:<64-lowercase-hex>`.
`go_router` receives raw path-parameter values and owns URI encoding.

```dart
abstract interface class AssignmentDetailStore {
  Stream<StoredAssignmentDetail> watch(AssignmentDetailKey key);
}

abstract interface class AssignmentDetailService {
  Stream<AssignmentDetailState> watch(AssignmentDetailKey key);
}
```

Both interfaces emit redacted, bounded application-owned values. Public
presentation state contains no raw HTML, generated Drift row, notification ID,
dedupe key, user ID, or opaque backend JSON.

## Data model

No table, column, index, or migration changed; schema remains version 7.

The detail reader observes:

- `activities` and `courses` for the current verified display record.
- `seen_activities` for durable observation evidence.
- `course_preferences` for the local per-course mute value.
- `scheduled_reminders` for counts, reconciliation count, and the earliest
  non-pending scheduled time.
- `notification_history` for count and latest local record time.
- `sync_runs` for the latest retained attempt and success.

Every assignment query filters both semester ID and identity key. Sync queries
filter the explicit route semester. The reader does not inspect
`app_settings`, credentials, user identity, submissions, questions, files, or
other opaque JSON.

## State and control flow

1. The router decodes path parameters and validates `AssignmentDetailKey`.
2. Invalid input renders safe local-link copy without constructing the store.
3. A valid route loads the shared database-backed service.
4. The store observes seven local tables and reads one coherent transaction.
5. Current content is sanitized before the service emits presentation state.
6. The page renders current, seen-only, or missing state.
7. A committed reconciliation can transition current to seen-only.
8. A later stream error preserves the last state and marks the local view
   stale.
9. Back pops an in-app detail; a direct cold-start route goes safely to the
   assignment dashboard.

The explicit route key remains authoritative and never retargets from the
active-semester setting.

## Platform behavior

The Dart implementation is shared by Android, iOS, Windows, macOS, and Linux.
Compact and medium windows use one scrolling document. Expanded windows use a
content column and narrow evidence rail within the same bounded route.
Material surfaces provide pointer, focus, pressed, and keyboard activation.

Linux is the only native host available for build verification in this
feature. Other platform behavior is implemented in shared Flutter code but
not build-verified here.

## Security and privacy

Raw assignment descriptions are untrusted. The `html` parser removes
`script`, `style`, `template`, `noscript`, `iframe`, `object`, `embed`, `svg`,
and `canvas` subtrees. It also removes an entire element subtree when the
boolean `hidden` attribute is present, when a trimmed case-insensitive
`aria-hidden` value is `true`, or when a conservatively parsed inline
declaration has `display: none`, `visibility: hidden`, or
`content-visibility: hidden`. Inline property/value comparison is
case-insensitive, tolerates surrounding whitespace and CSS comments, ignores
an optional `!important` suffix, and treats any matching declaration as
hidden rather than evaluating the CSS cascade.

Comments and all remaining attributes are ignored; only decoded inert text is
emitted. Visible anchor text survives, but its URL and attributes do not.
Before processing visible block descendants, the sanitizer establishes one
paragraph boundary when prior visible inline output lacks one. Nested,
consecutive, and empty blocks reuse an existing boundary instead of adding
blank lines. Paragraph, line-break, and list boundaries are therefore retained
without leading whitespace. No WebView, HTML renderer, URL launcher, or tap
action is created from source content.

Generated Drift rows, raw HTML, opaque JSON, credentials, authorization
headers, user IDs, route inputs, and exception messages are not logged or
exposed through public debug representations. The route contains only the
non-secret local semester and stable identity.

Notification and reminder copy reports only records and reconciliation
evidence. It never claims OS delivery, display, permission, or cancellation.

## Decisions

- Use the parser-backed `html` package rather than a regex tag stripper.
- Keep the detail identity explicitly semester-scoped.
- Define Seen-only assignment as durable prior observation without current
  snapshot content.
- Treat the service as a security boundary instead of passing data-layer
  values to widgets.
- Preserve valid rendered state after a later local-read error.
- Use a flat Record Sheet rather than nested metric cards or a new
  master-detail state graph.
- Keep deadline-exceeded status sourced only from the saved backend flag.

## Alternatives rejected

- `flutter_html`, WebView, and `url_launcher`: no typed external URL contract
  exists and executable HTML is out of scope.
- Regex-only sanitization: malformed markup and entity decoding would remain
  unsafe or unreadable.
- Identity without semester: the same activity identity can exist in multiple
  semesters.
- Showing opaque attachment/submission JSON: upstream element contracts are
  not verified.
- Labelling `createdAt` as Published: the backend does not define that
  meaning.
- Keeping removed title/description in a new table: that would expand schema
  and retention policy beyond this feature.

## Failure behavior

Invalid route values show “Assignment link unavailable” without echoing the
path or touching Drift. Initial provider and stream failures show bounded
local-storage errors with retry. A later stream failure retains the last
record and displays a stale-local-read banner.

Missing sync success evidence is reported as unavailable. A latest failed or
cancelled attempt marks local assignment data stale. The banner uses
state-neutral wording and never claims a missing assignment is saved.
Network-unavailable evidence describes the retained last attempt and is not
presented as live connectivity.

## Tests

- Key tests cover backend/fingerprint formats, positive-int32 bounds, equality,
  raw named parameters, and redaction.
- Sanitizer tests cover plain text, blocks, lists, line breaks, entities,
  malformed markup, active/embedded containers, boolean/ARIA/inline-style
  hidden subtrees, visible siblings, inert anchor text, inline-to-block
  boundaries, nested/empty blocks, duplicate-boundary avoidance, empty input,
  and redaction.
- Store tests cover current safe fields, direct same-semester/different-identity
  and same-identity/different-semester aggregate isolation, explicit-semester
  sync evidence, latest attempt/success ordering, current-to-seen-only commit,
  absent course, missing identity, rollback, and redaction.
- Service tests cover sanitizer enforcement, timestamp classification,
  current/seen-only/missing mapping, evidence mapping, and bounded failures.
- Page tests cover factual copy, distinct states, neutral missing-state stale
  copy, direct zoned-local and unzoned-wall-clock rendering, later-error
  preservation, retry, semantics, long multilingual content, and 200% scaling
  from 320 to 1200 logical pixels.
- Route/router/dashboard tests cover invalid-input short-circuiting, URI
  encoding, fingerprint round-trip, guards, shell retention, expired banner,
  compact and expanded activation, keyboard intent, push/back behavior, and
  bounded provider states.

## Validation evidence

- `flutter pub get` — passed; resolved `html 0.15.6` and `csslib 1.0.2`.
- The final inline-to-block regression reproduced `beforeafter` before the
  repair and passed after the idempotent paragraph-boundary fix.
- Sanitizer tests — 10 tests passed.
- All assignment-detail tests — 33 tests passed.
- `dart run build_runner build --delete-conflicting-outputs` — passed; the
  final pass wrote 44 same outputs and an immediate repeat wrote zero,
  confirming generated-code stability with no generated diff.
- `dart format --output=none --set-exit-if-changed .` — passed; 139 files
  checked with zero changes.
- `dart analyze --fatal-infos --fatal-warnings` — passed with no issues.
- `flutter analyze --fatal-infos --fatal-warnings` — passed with no issues.
- Exact non-golden detail/dashboard/router/dependency focused command — 86
  tests passed.
- Dashboard golden refresh — two intentional baselines updated after Material
  row activation changed RepaintBoundary compositing; both candidates were
  visually inspected. The final ordinary golden run passed both tests without
  updating either baseline.
- Combined non-golden and ordinary-golden focused total — 88 tests passed.
- `flutter test --reporter failures-only` — 514 tests passed.
- `flutter build linux --release` — passed; produced
  `build/linux/x64/release/bundle/leb2-watch`.
- `git diff --check` — passed.
- Production secret, prohibited-scope, TODO, FIXME, and placeholder scans —
  no matches in the assignment-detail implementation.

## Known limitations

- Attachments and external links remain hidden because their typed upstream
  schemas are not verified.
- Class-based or external-stylesheet visibility is not evaluated. The
  sanitizer enforces the explicit semantic attributes and inline declarations
  documented above without rendering or applying CSS.
- Exact deadline inclusivity and unzoned timezone semantics remain undefined.
- Seen-only state retains no title or description because the current row owns
  those fields.
- Notification history proves only a local record, not OS display or delivery.
- Retained sync history is globally bounded, so a valid cache can lack a
  retained successful timestamp.
- Cold-start detail intent is not preserved through onboarding,
  authentication, or semester-selection redirects unless it arrived through
  the validated local-notification target coordinator.

## Future considerations

Features 12.2 and 12.3 can use the established local-notification service
without changing the detail route identity. A later verified backend contract
may add typed attachments or external links. Future notification features may
enrich local evidence without changing the current sanitization boundary.

## Related contexts

- [Backend API Contract](backend-api-contract.md)
- [Local Database](local-database.md)
- [Assignment Diffing](assignment-diffing.md)
- [Assignment Synchronization](assignment-synchronization.md)
- [Local-First Assignment Dashboard](assignment-dashboard.md)
- [Adaptive Application Shell](adaptive-app-shell.md)
- [Flutter Dependencies and Code Generation](flutter-dependencies-and-codegen.md)
- [Course Preferences](course-preferences.md)
- [Local Notification Service](local-notifications.md)
