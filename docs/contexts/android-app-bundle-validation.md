# Android App Bundle Validation

## Status

Completed for one sanitized, external-test-key Release AAB artifact. This is
an artifact-only validation record, not an Android runtime or distribution
approval.

## Purpose

Give self-hosting operators a reproducible local record for the Android App
Bundle packaging format before they introduce their own production signing or
distribution process.

## Scope

- Build one Release AAB with `APP_ENV=production` and the invalid placeholder
  origin `https://backend.example.invalid`.
- Use the existing ignored configuration that references an external,
  validation-only signing identity.
- Record the output path, SHA-256, ZIP integrity, bounded required-entry
  inventory, archive-signature result, and bounded forbidden-entry check.
- Document the distinction between archive signature integrity and JDK
  certificate-chain trust.

## Non-scope

- Reading, changing, exporting, or committing the signing configuration,
  certificate, key, or password.
- A production backend, user credential, network request, user data, or
  production signing identity.
- Bundletool acquisition or use, AAB-derived APK generation, installation,
  emulator/device runtime, Google Play upload, Play App Signing, or release
  distribution.

## User-visible behavior

None. The AAB is a distribution input, not an installable application. The
previous APK/emulator foreground evidence remains the runtime evidence.

## Architecture

`android/app/build.gradle.kts` conditionally applies an ignored
`android/key.properties` release configuration. Flutter's `bundleRelease`
path uses that Release build type. No app source or Gradle logic changed for
this validation.

## Important files

- `android/app/build.gradle.kts` — existing conditional Release signing
  contract.
- `android/.gitignore` — excludes local signing properties and keystore files.
- `test/platform/android/android_release_signing_configuration_test.dart` —
  guards the no-debug-fallback and signing-redaction policy.
- `docs/configuration-and-builds.md` — operator build instructions and AAB
  boundary.
- `docs/contexts/platform-build-validation.md` — cross-platform validation
  evidence.

## Contracts and interfaces

The operator build command is:

```text
flutter build appbundle --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://backend.example.invalid
```

The output inspected was:

```text
build/app/outputs/bundle/release/app-release.aab
SHA-256: e5e1d775cd6437cb9d4bb24ebc2e49ccfb5c463f0752a9811857e9edcf32b084
```

The placeholder origin is intentionally invalid and proves no backend request.
For a real operator release, replace it only at rebuild time with that
operator's self-hosted HTTPS origin.

## Data model

This validation adds no application data, schema, credential, or transport
model. The generated AAB is a local build artifact and is not tracked.

## State and control flow

1. Flutter invokes Gradle's `bundleRelease` task with sanitized Dart defines.
2. The ignored external test signing configuration signs the Release artifact.
3. The output AAB is checked as a ZIP and for bounded required/forbidden
   entries.
4. `jarsigner` verifies embedded archive signatures.
5. The strict JDK diagnostic separately exposes certificate-chain trust.

## Platform behavior

This evidence was collected on the Linux Android build host with its
user-owned JDK 17 and Android SDK. An AAB cannot be installed directly with
`adb`; platform/runtime evidence requires a separately scoped APK-set or APK
validation on a target device.

## Security and privacy

No key, password, alias, certificate fingerprint, backend credential, session
cookie, or user data was printed or committed. The output inventory check
found no `key.properties`, `.jks`, `.keystore`, PEM, or private-key entry.
The build used only `https://backend.example.invalid`.

## Decisions

- Use `unzip -t` for container integrity and `jarsigner -verify` for the
  signed ZIP/JAR archive result.
- Preserve `jarsigner -verify -strict -certs` as a diagnostic rather than
  hiding its nonzero result.
- Do not use `apksigner`, which verifies APKs rather than AABs.
- Do not repurpose Gradle's non-runnable cached Bundletool module as the
  standalone Bundletool CLI.

## Alternatives rejected

- Trusting the self-signed test certificate in a local JDK store: would only
  prove a deliberately modified local trust policy and expands the signing
  boundary.
- Disabling strict verification or reporting its result as a pass: would hide
  the exact chain-trust limitation.
- Installing Bundletool during this feature: separate tool acquisition and
  APK-set/device validation are outside artifact-only scope.

## Failure behavior

The sanitized build succeeded. ZIP integrity succeeded. `jarsigner -verify`
exited `0` with `jar verified.` It still emitted its self-signed/untrusted
chain, missing timestamp, POSIX-attribute, and JarFile/JarInputStream
consistency warnings. The stricter
`jarsigner -verify -strict -certs` exited `4` with `jar verified, with signer
errors.` JDK 17 reports that the validation signer is self-signed and has no
trusted path in its default trust store. The strict exit is not an archive
signature or ZIP-integrity failure, but trusted-chain verification remains
unproven.

## Tests

`test/platform/android/android_release_signing_configuration_test.dart`
continues to cover the existing local signing contract, ignored signing files,
redacted failure behavior, no debug signing fallback, and narrow Room/R8 rule.
No app code or executable signing contract changed, so no new test was added.

## Validation evidence

- `flutter build appbundle --release` with sanitized production defines:
  passed; output was `app-release.aab` (63.9 MB).
- `sha256sum`: recorded the SHA-256 above.
- `unzip -t`: exit `0`, no compressed-data errors.
- Bounded archive inventory: required `BundleConfig.pb`, base manifest, and
  two DEX files present; forbidden signing/configuration entries absent.
- `jarsigner -verify`: exit `0`, `jar verified.` The non-strict command still
  reported its self-signed/untrusted chain, missing timestamp, POSIX-attribute,
  and JarFile/JarInputStream consistency warnings.
- `jarsigner -verify -strict -certs`: exit `4`, self-signed/untrusted-chain
  diagnostic; not a strict-trust pass.
- The full 1,097-test/14-shard host-suite result predates this documentation-
  only feature change and is historical rather than fresh AAB-feature test
  evidence. Focused tests and no-write checks are recorded with this feature.

## Known limitations

- No standalone Bundletool validation is available locally.
- No trusted certificate-chain result exists for the external test signer.
- No APK set was generated or installed from this AAB.
- No runtime, Play acceptance, Play App Signing, store, production signer, or
  physical-device conclusion follows from this artifact validation.

## Future considerations

Separately acquire and verify a standalone Bundletool release if device-
targeted APK-set validation is needed. Validate a real operator-signed release
through the operator's distribution process without committing keys or
credentials.

## Related contexts

- `docs/contexts/platform-build-validation.md`
- `docs/contexts/android-background-sync.md`
- `docs/contexts/android-local-notification-runtime-validation.md`
