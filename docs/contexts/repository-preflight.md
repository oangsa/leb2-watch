# Repository Frontend Preflight

## Status

Completed. This status covers the repository inspection record only; no Flutter
application feature has been implemented.

## Purpose

Establish the current repository, SDK, and host-toolchain state before LEB2
Watch frontend work begins. This prevents later features from assuming that
application source, backend contracts, or platform build support already exist.

## Scope

- Repository contents and instruction-file inventory.
- Current Git branch, HEAD, index, and working-tree state.
- Presence of frontend, backend, OpenAPI, fixture, documentation, and test
  sources in the current checkout.
- Installed Flutter and Dart versions.
- Host readiness for Android, iOS, Windows, macOS, and Linux builds.

The inspection was performed on 2026-07-25 on x86-64 Arch Linux, kernel
`7.1.3-arch1-2`.

## Non-scope

- Scaffolding or configuring a Flutter project.
- Installing SDKs, platform toolchains, or dependencies.
- Fetching remote Git state.
- Inferring or implementing an API contract.
- Running application tests or builds when no application project exists.

## User-visible behavior

None. This feature changes documentation only and does not add or modify
product behavior.

## Architecture

There is no application architecture in the current checkout. A new Flutter
project is required because `pubspec.yaml`, `lib/`, generated platform
directories, and test sources are absent.

No frontend or backend location exists in this checkout:

- Frontend source: absent.
- Backend source: absent.
- OpenAPI documents, API fixtures, and API documentation: absent.

The repository root is a possible future scaffold location, but that location
has not been verified by existing repository evidence.

## Important files

- `AGENTS.md` — repository-wide workflow, validation, context, and commit rules;
  it is the only file in the inspected HEAD.
- `docs/contexts/repository-preflight.md` — this inspection record.

There are no nested `AGENTS.md` files and no earlier files under
`docs/contexts`.

## Contracts and interfaces

No backend API contract or application interface can be verified from the
current checkout. In particular, authentication behavior, endpoints, response
models, errors, and timestamp semantics remain unverified and must not be
invented.

Flutter and Dart are available only after shell initialization. In each newly
opened terminal that does not already expose them, run:

```bash
source ~/.zshrc
```

Run that initialization once for the terminal before its first Flutter or Dart
command, not before every command.

## Data model

No local database, tables, migrations, fixtures, or application models exist.
No credential fields or user-specific data were introduced by this
documentation feature.

## State and control flow

At the time of inspection:

- Branch: `dev`.
- HEAD: `e25b0b3 Innitial commit`.
- Local `main` and the cached `origin/main` ref also point to `e25b0b3`.
- The index and working tree were clean before this document was created.
- There are no Git submodules.
- The only configured remote is an SSH GitHub remote for this repository; no
  fetch or other remote-state change was performed.

Future application state and control flow are not defined by this feature.

## Platform behavior

Verified SDK versions after initializing one login-shell terminal:

- Flutter `3.44.8`, stable, framework revision `058e0af2c2`.
- Dart `3.12.2`, stable, Linux x64.
- DevTools `2.57.0`.

The first successful Flutter invocation initialized Flutter's user-owned SDK
cache outside this repository. It did not modify repository files.

Current host readiness is:

| Target | Status | Evidence and remaining requirement |
| --- | --- | --- |
| Linux | Toolchain ready; application build unverified | `flutter doctor -v` passed the Linux toolchain and detected a Linux desktop device. Clang 22.1.8, CMake 4.4.0, Ninja 1.13.2, pkg-config 3.0.3, and GTK 3.24.52 are present. Run `flutter build linux` after scaffolding. |
| Android | Not ready | Flutter could not locate an Android SDK. Java, Android SDK command-line tools, ADB, and the emulator were not found. Install and configure the required toolchain, then run `flutter build apk` after scaffolding. |
| iOS | Not buildable on this host | Linux cannot perform an iOS application build, and Xcode/CocoaPods are absent. On a configured macOS host, run `flutter build ios --no-codesign`. |
| macOS | Not buildable on this host | A macOS host and Xcode are required. On a configured macOS host, run `flutter build macos`. |
| Windows | Not buildable with this host/toolchain | Windows/MSVC tools are absent. On a configured Windows host, run `flutter build windows`. |

`flutter doctor -v` also reported Chrome absent. Web is not a requested target.
`flutter devices` did not return before it was interrupted, so that command is
unverified; the Linux device claim above comes from `flutter doctor -v`.

No application build was attempted because no Flutter project exists. Host
toolchain readiness is not a successful build result.

## Security and privacy

No credentials, user data, API payloads, secrets, or production URLs were
present or added. No remote service was contacted for product data, and no
backend contract was inferred from a repository name or remote metadata.

## Decisions

- Require a new Flutter scaffold rather than treating this repository as an
  existing application.
- Record absent backend and OpenAPI sources as a blocker for contract
  verification instead of inventing fields or endpoints.
- Classify Linux as toolchain-ready but not build-verified.
- Leave remote-only repository state unverified because remote fetching is
  outside this feature.

## Alternatives rejected

- Scaffolding during preflight was rejected because it belongs to the separate
  Flutter scaffold feature.
- Treating `flutter doctor` as an application build was rejected because no
  application source exists.
- Guessing a backend contract or searching remote-only state was rejected
  because neither is supported by current-checkout evidence or this feature's
  scope.

## Failure behavior

This feature contains no runtime failure handling. Inspection limitations are
reported rather than hidden:

- Backend contract verification cannot proceed from the current checkout.
- Android builds require an Android SDK and Java toolchain.
- Apple builds require a configured macOS host.
- Windows builds require a configured Windows/MSVC host.
- Any real platform build remains pending until the Flutter project exists.

## Tests

No automated tests were added or run. There is no Flutter project, test source,
or behavior change to test.

## Validation evidence

Repository inspection included:

```bash
git status --short --branch
git branch --show-current
git log --oneline --decorate --all -10
git diff --stat
git diff --staged --stat
git ls-tree -r --name-only HEAD
git submodule status
find . -name AGENTS.md -type f -print
```

The results established branch `dev`, HEAD `e25b0b3`, a clean starting index
and working tree, no submodules, and only the root `AGENTS.md`.

After one `source ~/.zshrc` in a newly opened terminal, SDK and host validation
included:

```bash
flutter --version
dart --version
flutter doctor -v
flutter config --list
```

Flutter and Dart version checks passed. Flutter Doctor passed the Flutter and
Linux desktop categories and reported missing Android and Chrome toolchains.
No application tests or builds were run for the reasons documented above.

Documentation-specific validation:

```bash
git diff --check
git diff --no-index --check /dev/null docs/contexts/repository-preflight.md
git status --short
```

Both whitespace checks completed without errors; the no-index command returned
the expected status indicating that the new file differs from `/dev/null`.
Status showed only the new `docs/` path. A targeted secret-pattern scan returned
no matches, and the complete document was reviewed for unrelated changes and
secret-like content.

## Known limitations

- Backend source, API documentation, OpenAPI definitions, and sanitized
  fixtures are unavailable in the current checkout.
- Remote-only branches and files were not inspected.
- The intended Flutter scaffold directory is not proven by repository
  evidence.
- Real application compilation, device enumeration through `flutter devices`,
  and all platform builds remain unverified.
- Android, Apple, and Windows toolchains are not currently available on this
  host as described under Platform behavior.

## Future considerations

- Obtain an authoritative backend source, OpenAPI document, or API
  documentation before backend contract verification.
- Confirm the Flutter scaffold location, then implement the cross-platform
  scaffold as its own feature.
- Install the Android SDK and Java prerequisites before Android build
  validation.
- Perform Apple and Windows build validation on their native hosts.

## Related contexts

None. This is the first context document in the repository.
