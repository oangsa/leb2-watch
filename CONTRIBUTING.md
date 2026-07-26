# Contributing to LEB2 Watch

Thank you for helping improve LEB2 Watch. Keep contributions small,
evidence-backed, local-first, and honest about platform validation.

## Before contributing

This frontend and its backend repository are publicly visible but do not yet
include licenses or contribution terms. Public visibility does not grant
general permission to use, modify, or redistribute the code. The owner must
choose licenses for both repositories and decide whether ordinary license
terms, a DCO, or a CLA applies.

Do not include a license, copyright identity, security contact, or contribution
agreement on the owner's behalf.

## Choose a scope

- Open or reference an issue that states the user-visible outcome.
- Keep one coherent feature or fix per pull request.
- Avoid unrelated refactors, dependency updates, formatting, and cleanup.
- Preserve local-first data ownership and the self-hosted backend boundary.
- Document unsupported or host-unverified behavior instead of presenting it
  as complete.

Changes to the backend belong in the
[LEB2SCRAPPER-API](https://github.com/oangsa/LEB2SCRAPPER-API) repository.
Coordinate contract changes across both repositories.

## Set up

Use Flutter `3.44.8` stable with Dart `3.12.2`:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Run against a reachable non-production backend:

```bash
flutter run -d <DEVICE_ID> \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://<REACHABLE_HOST>:5015
```

Read [Development](docs/development.md) for architecture, generation, and test
details.

## Test the behavior

Add the narrowest test that proves the requested outcome:

- unit tests for domain logic;
- Drift tests for schema, migration, transaction, and persistence behavior;
- fake transport tests for API/error behavior;
- widget and golden tests for responsive UI;
- integration tests for complete mocked workflows; and
- native/static tests for custom platform configuration.

Automated tests must use sanitized fixtures. Never call the production backend
or LEB2 and never use a real cookie, password, user ID, assignment, or personal
identifier.

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

Run only native builds supported by the current host. State exactly which
builds and device tests were not run.

## Generated files

`*.g.dart` and `*.freezed.dart` are committed. Modify their annotated sources,
regenerate, review the generated diff, and commit it with the owning change.
Do not edit generated files manually.

## Documentation

Update the relevant public guide when setup, configuration, privacy, platform
behavior, or limitations change.

Maintainer-directed feature work also updates one technical continuation file
under `docs/contexts/` with:

- scope and non-scope;
- user-visible behavior;
- architecture/contracts;
- privacy/failure behavior;
- tests and actual validation evidence; and
- known limitations.

## Commits and pull requests

Repository commit prefixes are:

- `feat:` new or completed behavior;
- `fix:` corrected behavior;
- `style:` formatting only;
- `refactor:` structure without behavior changes; and
- `chore:` tooling, configuration, maintenance, or documentation.

Before submitting:

- review every changed file;
- remove temporary logs and artifacts;
- confirm generated code is synchronized;
- search for credentials and personal data;
- run relevant focused tests and repository gates;
- document native validation gaps; and
- explain the user-visible result and evidence in the pull request.

## Sensitive reports

There is not yet a documented private vulnerability-reporting channel. Do not
paste session cookies, credentials, assignment data, authorization headers,
private certificates, or raw sensitive logs into a public issue or pull
request. A private reporting mechanism remains an owner decision and release
blocker.
