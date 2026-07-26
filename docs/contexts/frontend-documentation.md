# Frontend Documentation

## Status

Completed. The public bring-your-own-backend documentation is reconciled with
the committed Phase 16 integration and Phase 17.1 validation evidence and is
cross-linked for users, operators, and contributors.

This documentation feature is complete; it does not resolve the separate
release blockers: both repositories lack licenses, no private security
reporting mechanism is designated, and the compatible backend revision is not
on that repository's default branch or a tagged release.

## Purpose

Give users, self-hosters, contributors, and future maintainers one accurate
entry point for running LEB2 Watch without implying that the author provides a
hosted service or that unverified platforms are release-ready.

## Scope

- A role-oriented README.
- Compatible-backend and self-hosting guidance.
- Compile-time configuration, run, validation, and build commands.
- Public architecture and local-first data ownership.
- Device/backend privacy boundaries and deletion behavior.
- Honest platform implementation/build status.
- Contributor and troubleshooting guides.
- Explicit license, backend-release, frontend-publication, and
  security-reporting blockers.

## Non-scope

- Choosing or creating a license.
- Inventing a copyright holder, year, CLA, DCO, or security contact.
- Editing or validating the sibling backend implementation.
- Publishing a backend or frontend release.
- Adding an in-app server selector, proxy support, packaging, signing, or
  deployment automation.
- Claiming native build or runtime results unavailable on the current host.

## User-visible behavior

The repository landing page now explains:

- what the local-first application does;
- the exact third-party/non-affiliation disclaimer;
- that no author-operated backend exists;
- that each operator deploys, secures, monitors, and pays for a compatible
  backend;
- which backend revision is compatible;
- how data moves and where it is retained;
- the current platform-validation boundary; and
- where users, operators, and contributors should continue.

Public guides provide copyable placeholder-based commands without embedding a
production URL, credential, signing secret, or personal identifier.

## Architecture

Public documentation is split by reader intent:

- `README.md` — landing page, hosting model, status, and path selection.
- `docs/self-hosting-backend.md` — pinned backend revision, .NET/Docker/Cloud
  Run facts, health semantics, and operator responsibilities.
- `docs/configuration-and-builds.md` — compile-time definitions, run/build
  commands, and release ownership.
- `docs/architecture.md` — local-first layers, data flow, synchronization, and
  storage ownership.
- `docs/privacy-and-security.md` — device/backend boundaries, logging,
  deletion, and reporting limitation.
- `docs/platform-support.md` — implementation, validation, and per-platform
  constraints.
- `docs/development.md` — contributor toolchain, generation, tests, contexts,
  and CI.
- `docs/troubleshooting.md` — verified failure modes and safe recovery.
- `CONTRIBUTING.md` — small-scope human contribution expectations.

Canonical facts live in the most specific guide and are linked from the
README. Detailed implementation history remains in `docs/contexts/`.

## Important files

- `README.md` — public landing page.
- `docs/self-hosting-backend.md` — BYO backend guide.
- `docs/configuration-and-builds.md` — frontend configuration/build guide.
- `docs/architecture.md` — public technical overview.
- `docs/privacy-and-security.md` — privacy/security boundary.
- `docs/platform-support.md` — platform matrix and limitations.
- `docs/development.md` — contributor development workflow.
- `docs/troubleshooting.md` — recovery guide.
- `CONTRIBUTING.md` — public contribution guide.
- `docs/contexts/frontend-documentation.md` — this continuation record.

## Contracts and interfaces

Documentation pins the compatible backend to:

```text
repository: https://github.com/oangsa/LEB2SCRAPPER-API
commit:     d6e3261537c53507873f36de166f6245bc82fcc4
```

The backend default `main` branch is documented as incompatible until a
verified release changes that fact.

The frontend accepts exactly:

```text
APP_ENV=development|production
BACKEND_BASE_URL=<absolute-root-origin>
```

The guides state that these are Dart compile-time definitions, a production
origin must use HTTPS, path-hosting is unsupported, and changing servers
requires rebuilding.

## Data model

Documentation adds no runtime data or schema. It describes:

- secrets in OS secure storage;
- cached assignment and coordination state in Drift/SQLite;
- notification and reminder ownership in SQLite; and
- request-scoped plus short-lived process-memory data on the backend.

It deliberately avoids the inaccurate claim that the backend never holds user
data.

## State and control flow

Reader flow:

1. README identifies whether the reader needs the app, backend, or contributor
   path.
2. Self-hosters pin and deploy the verified backend revision.
3. App builders supply a reachable root origin at compile time.
4. Platform guidance separates static validation from native build/runtime
   validation.
5. Privacy guidance describes both device and operator boundaries before
   credential entry.
6. Troubleshooting maps known conditions to safe, non-secret checks.

## Platform behavior

The public matrix reports Linux as release-build verified. Android, iOS,
macOS, and Windows are described as implemented and statically/focused-test
validated but not native-build verified on the Linux host.

The guides document:

- Android WorkManager limits and operator-local release signing that never
  falls back to debug;
- iOS 14+, best-effort BGAppRefresh, and required macOS/device validation;
- macOS 10.15+, tray/autostart behavior, and signing/notarization gaps;
- unpackaged Windows notification and packaging limits; and
- Linux keyring, tray, scheduled-notification, and packaging limits.

The startup description records the production local-only stage resolver and
cache-first dashboard behavior. The integration workflow removes and rebuilds
the widget/provider graph and closes/reopens one SQLite file inside a single
Linux test executable; it does not claim a separate OS-process relaunch.

## Security and privacy

- No hosted URL, credential, authorization header, API key, signing secret, or
  personal data is documented.
- Operator responsibilities include TLS, logging, abuse controls, cost/quotas,
  provider intermediaries, and updates.
- The backend's tracked user publish-profile metadata is called out for manual
  security review without reproducing the high-entropy value.
- Public reporting guidance says never to submit credentials or sensitive
  user data.
- `SECURITY.md` is intentionally absent because no private contact/mechanism
  has been selected.
- `LICENSE` is intentionally absent because no license has been selected.

## Decisions

- Use “publicly visible” and “source-available,” not “open source,” until
  licenses are committed.
- Pin a commit rather than suggesting an incompatible default-branch clone.
- Make operator ownership/cost prominent rather than burying it in deployment
  details.
- Document Cloud Run as one optional example, not an official hosting path.
- Keep one canonical detailed guide per topic and use links from the README.
- Describe current verified behavior rather than future distribution plans.
- Omit a `SECURITY.md` that would have to invent a reporting address.

## Alternatives rejected

- Selecting MIT, Apache-2.0, GPL, or another license without owner approval.
- Calling public repositories open source without reuse rights.
- Publishing an author-hosted backend URL, SLA, pricing, or free-hosting claim.
- Documenting generic reverse-proxy, Kubernetes, package-store, emulator, or
  signing recipes that have not been verified.
- Calling static configuration tests native builds.
- Claiming the backend never sees or holds user data.
- Duplicating every internal feature context in the public guides.

## Failure behavior

Documentation maps invalid/missing/root-path backend URLs, HTTP in production,
an incompatible backend 404/response shape, device-localhost mistakes,
health-200/degraded responses, Selenium failures, missing user-ID headers,
session expiration, codegen warnings, keyring failures, delayed background
work, suppressed notifications, unsupported scheduling, desktop process
requirements, and native toolchain gaps.

Every recovery path avoids weakening TLS or asking users to expose secrets.

## Tests

Documentation validation covers:

- relative Markdown links;
- command and backend-revision consistency;
- exact third-party disclaimer;
- no author-hosted-backend implication;
- no unsupported open-source claim;
- placeholder/secret/personal-data scan;
- whitespace/diff checks; and
- final repository formatting, analysis, tests, and supported builds through
  the Phase 17 validation evidence.

## Validation evidence

Phase 16 integration evidence:

```text
flutter test integration_test/end_to_end_mocked_workflow_test.dart \
  -d linux --reporter expanded
```

The Linux debug application built and the workflow passed 1/1. Its isolated
Phase 16 source copy also passed 859/859 ordinary tests, both strict analyzers,
formatting across 285 files with 0 changes, two code-generation passes with
the second writing 0 outputs, and a Linux release build. See
[Frontend integration testing](frontend-integration-testing.md).

The committed Phase 17.1 hardening evidence is:

```text
Focused router/privacy/Settings/signing suites: 53 passed
dart analyze --fatal-infos: no issues
flutter analyze --fatal-infos --fatal-warnings: no issues
flutter test --reporter compact: 857 passed
dart run build_runner build --delete-conflicting-outputs:
  completed; 4 synchronized Drift outputs, no generated file in final status
flutter build linux --release:
  built build/linux/x64/release/bundle/leb2-watch
```

Android signing-material inventory found no tracked or local
`key.properties`, `.jks`, `.keystore`, `.p12`, `.pem`, or `.key` file.
Product-source scans found no debug release-signing fallback, unfinished
template signing marker, or generic privacy placeholder. Android native build
and certificate validation remain unavailable. See
[Platform build validation](platform-build-validation.md).

The Markdown-only closeout then rechecked all ten documentation files for
relative links, whitespace/final newlines, the exact disclaimer, public work
markers, common secret-value patterns, unsupported success claims, backend
revision consistency, and Android release-signing consistency.

A fresh standards review and spec/security review found two documentation
issues, both closed in scope: the architecture now distinguishes the backend's
lack of durable per-user storage from its process-local state, and the README
and self-hosting guide place the no-license/use-permission boundary before any
deployment command.

## Known limitations

- Both repositories lack licenses. This is a release blocker; the owner must
  choose whether they share a license and supply the copyright identity/year.
- Contribution terms (ordinary license grant, DCO, or CLA) are undecided.
- There is no designated private security-reporting channel. This is a release
  blocker.
- The compatible backend code is not on its current default branch or tagged
  release. This is a release blocker because an unqualified clone is
  incompatible with the frontend.
- The frontend implementation was not on its public default branch at research
  time.
- No fresh backend build, Docker build, server run, or Cloud Run deployment was
  performed by this frontend documentation feature.
- Android, Apple, and Windows native builds were not available on this Linux
  host.
- Signing and distribution packaging remain operator-owned and unverified.

## Future considerations

- Choose and commit licenses in both repositories.
- Merge/tag the compatible backend revision and publish a compatibility policy.
- Establish private security reporting and supported-release policy.
- Add an optional runtime backend selector only as a separate privacy and
  distribution feature.
- Add verified signing/packaging instructions after native release pipelines
  exist.

## Related contexts

- [Repository preflight](repository-preflight.md)
- [Verified backend contract](backend-api-contract.md)
- [Flutter scaffold](flutter-project-scaffold.md)
- [Dependencies and code generation](flutter-dependencies-and-codegen.md)
- [Privacy onboarding](privacy-onboarding.md)
- [Local data deletion](local-data-deletion.md)
- [Frontend integration testing](frontend-integration-testing.md)
- [Platform build validation](platform-build-validation.md)
