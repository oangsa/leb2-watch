# Development

This guide is for frontend contributors. Backend operators should start with
[Self-hosting the backend](self-hosting-backend.md).

## Toolchain

The verified baseline is:

```text
Flutter 3.44.8 stable
Dart 3.12.2
```

Install the native toolchain only for targets supported by the current host.
The repository contains Android, iOS, Linux, macOS, and Windows projects; it
does not contain a Flutter web target.

## Initial setup

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

The generator warning that `--delete-conflicting-outputs` is removed and
ignored is expected with pinned `build_runner 2.15.1`.

Run the application with a non-production backend that is reachable from the
selected device:

```bash
flutter run -d <DEVICE_ID> \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_BASE_URL=http://<REACHABLE_HOST>:5015
```

The backend value is a Dart compile-time definition, not a runtime shell
variable. See [Configuration and builds](configuration-and-builds.md).

## Repository map

```text
lib/
├── main.dart                   process entry point
├── bootstrap.dart              Flutter and root composition bootstrap
└── src/
    ├── app/                    routing, shell, theme, root providers
    ├── core/                   configuration, database, network, security
    ├── features/               user-facing and application feature modules
    └── platform/               mobile background and desktop native adapters

test/                           unit, database, transport, widget, and static tests
integration_test/               mocked end-to-end application workflows
docs/contexts/                  technical continuation records by feature
```

Application code imports native plugins only through application-owned
adapters. Widgets should not receive Dio, Drift, or plugin types. Transport
models stay separate from domain values.

## Generated code

Freezed, JSON, Riverpod, and Drift output is committed. Change the annotated
source, run the generator, review the output, and commit both together:

```bash
dart run build_runner build --delete-conflicting-outputs
```

To regenerate while editing:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

Do not edit `*.g.dart` or `*.freezed.dart` manually.

## Validation

Run the narrowest relevant test first, then the repository gates:

```bash
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

On a supported Linux host:

```bash
flutter build linux --release
```

Run the hermetic end-to-end workflow in a graphical Linux session:

```bash
flutter test integration_test/end_to_end_mocked_workflow_test.dart \
  -d linux --reporter expanded
```

The current recorded run built the Linux debug application and passed 2/2.
The first workflow covers opt-in automatic reauthentication after exact
expiration and one non-recursive continuation; the second gates a candidate
while credential deletion proves that no late cookie or credential commit can
restore deleted secrets. Both use sanitized in-process transport responses and
never contact LEB2 or a production backend. The restart portion removes and
rebuilds the widget/provider graph and closes/reopens the same SQLite file
within one test executable; it is not an operating-system process-relaunch
test.

Choose tests by behavior:

- domain rules: focused unit tests;
- Drift schemas, transactions, and migrations: in-memory and file-backed
  database tests;
- transport and failure mapping: fake adapter/server tests with sanitized
  fixtures;
- UI state and interactions: widget tests;
- important responsive layouts: golden tests;
- mocked user flows: integration tests;
- custom Kotlin, Swift, C++, or desktop setup: native tests where possible and
  static host checks elsewhere.

Do not delete valid tests, weaken assertions, or skip a failure solely to make
the suite pass. If the host cannot run a native test, record the exact gap.

## Test data and secrets

Automated tests must not:

- call the production backend or LEB2;
- use real cookies, usernames, passwords, user IDs, assignments, or personal
  identifiers;
- print Authorization headers or sensitive bodies;
- embed production URLs; or
- weaken TLS verification.

Add sanitized transport data under `test/fixtures/backend_api/`. Use obvious
placeholder values such as `<SESSION_COOKIE>` only in documentation, never as
working secrets.

## Feature contexts

`docs/contexts/` records the implementation boundary, contracts, decisions,
tests, validation evidence, and honest limitations of each completed feature.
When behavior changes, update the owning context in the same coherent commit.

Start with [Architecture](architecture.md), then follow the related-context
links for implementation details.

## CI

CI configures three jobs. The Ubuntu validation job:

1. resolves dependencies;
2. runs code generation;
3. checks tracked and untracked generated-code drift;
4. checks formatting;
5. runs Dart and Flutter analysis; and
6. runs `flutter test`.

It also defines a separate Linux/Xvfb integration job:

```bash
xvfb-run -a flutter test \
  integration_test/end_to_end_mocked_workflow_test.dart \
  -d linux
```

The same integration command passed locally in a graphical Linux session.
Execution of the Xvfb job on GitHub Actions has not yet been observed.

The Windows job checks Visual Studio C++/ATL prerequisites and builds the
complete unsigned, unpackaged Windows release directory with sanitized
compile-time definitions. It does not sign, package, publish, install, or
runtime-test the preview, and its remote result was not observed in this Linux
environment.

It grants `contents: read` and pins its top-level actions to immutable commits.
The Flutter setup action's internal cache action remains a transitive mutable
major tag when caching is enabled. CI does not publish artifacts. The
configured Windows compile gate becomes build evidence only after a successful
observed run and is never runtime evidence by itself.

## Before a pull request

- Review the diff and `git status`.
- Remove debug output and temporary files.
- Search changed files for secrets and personal data.
- Regenerate committed code.
- Run formatting, both analyzers, relevant focused tests, and the full test
  suite.
- Run only native builds available on the host and report the others as
  unverified.
- Update public and technical documentation when behavior or limitations
  change.

See [Contributing](../CONTRIBUTING.md) for repository expectations.
