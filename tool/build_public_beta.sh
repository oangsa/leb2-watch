#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly RELEASE_VERSION="0.5"
readonly EXPECTED_PUBSPEC_VERSION_PREFIX="0.5.0+"
readonly FLATPAK_APP_ID="dev.oangsa.leb2watch"
readonly FLATPAK_MANIFEST="${REPO_ROOT}/packaging/flatpak/${FLATPAK_APP_ID}.json"
readonly ARTIFACT_ROOT="${REPO_ROOT}/build/release-v${RELEASE_VERSION}"

BACKEND_BASE_URL="${BACKEND_BASE_URL:-}"
TARGET="${1:-all}"

usage() {
  cat <<'EOF'
Usage:
  BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN> \
    tool/build_public_beta.sh <android|flatpak|windows|macos|all>

Builds the LEB2 Watch v0.5 release artifact for one native target.
The all target is intentionally rejected: Flutter cannot build Flatpak,
Windows, and macOS artifacts from one host, so use the target-specific
commands on the required native hosts.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  "$@"
}

build_flutter_target() {
  local target="$1"
  printf '+ flutter build %s --release --dart-define=APP_ENV=production '
  printf -- '--dart-define=BACKEND_BASE_URL=<configured HTTPS origin>\n'
  flutter build "$target" --release \
    --dart-define=APP_ENV=production \
    "--dart-define=BACKEND_BASE_URL=${BACKEND_BASE_URL}"
}

host_name() {
  uname -s
}

target_supported_on_host() {
  local target="$1"
  case "$(host_name)" in
    Linux*)
      [[ "$target" == "android" || "$target" == "flatpak" ]]
      ;;
    Darwin*)
      [[ "$target" == "android" || "$target" == "macos" ]]
      ;;
    MINGW*|MSYS*|CYGWIN*)
      [[ "$target" == "android" || "$target" == "windows" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

check_release_version() {
  local pubspec_version
  pubspec_version="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
  [[ "$pubspec_version" == "${EXPECTED_PUBSPEC_VERSION_PREFIX}"* ]] || fail \
    "pubspec.yaml version is ${pubspec_version:-missing}; expected 0.5.0+<build> for release v${RELEASE_VERSION}"
}

check_backend_origin() {
  [[ -n "$BACKEND_BASE_URL" ]] || fail \
    'BACKEND_BASE_URL is required; provide the operator-owned HTTPS backend origin.'
  case "$BACKEND_BASE_URL" in
    https://*) ;;
    *) fail 'BACKEND_BASE_URL must use https:// for a production/release build.' ;;
  esac
}

run_validation() {
  run flutter pub get
  run dart run build_runner build --delete-conflicting-outputs
  run dart format --output=none --set-exit-if-changed .
  run dart analyze --fatal-infos --fatal-warnings
  run flutter analyze --fatal-infos --fatal-warnings
  run dart run tool/run_flutter_tests.dart
}

build_android() {
  build_flutter_target appbundle
  local artifact="${REPO_ROOT}/build/app/outputs/bundle/release/app-release.aab"
  [[ -f "$artifact" ]] || fail "Android AAB was not produced: $artifact"
  printf 'Android artifact: %s\n' "$artifact"
}

build_flatpak() {
  require_command flatpak-builder
  require_command flatpak
  build_flutter_target linux
  local flatpak_build="${ARTIFACT_ROOT}/flatpak-build"
  local flatpak_repo="${ARTIFACT_ROOT}/flatpak-repo"
  local flatpak_artifact="${ARTIFACT_ROOT}/leb2-watch-v${RELEASE_VERSION}.flatpak"
  run mkdir -p "$ARTIFACT_ROOT"
  run flatpak-builder --force-clean \
    --repo="$flatpak_repo" \
    "$flatpak_build" \
    "$FLATPAK_MANIFEST"
  run flatpak build-bundle \
    "$flatpak_repo" \
    "$flatpak_artifact" \
    "$FLATPAK_APP_ID"
  printf 'Flatpak artifact: %s\n' "$flatpak_artifact"
}

build_windows() {
  target_supported_on_host windows || fail \
    'Windows builds require a Windows host with Flutter desktop prerequisites and Visual Studio C++/ATL.'
  build_flutter_target windows
  local artifact="${REPO_ROOT}/build/windows/x64/runner/Release"
  [[ -d "$artifact" ]] || fail "Windows Release directory was not produced: $artifact"
  printf 'Windows artifact directory: %s\n' "$artifact"
  printf 'Windows native runtime status: not tested by this repository script.\n'
}

build_macos() {
  target_supported_on_host macos || fail \
    'macOS builds require macOS with Xcode and Flutter macOS desktop prerequisites.'
  build_flutter_target macos
  local artifact="${REPO_ROOT}/build/macos/Build/Products/Release/leb2_watch.app"
  [[ -d "$artifact" ]] || fail "macOS app bundle was not produced: $artifact"
  printf 'macOS artifact: %s\n' "$artifact"
  printf 'macOS native runtime status: not tested by this repository script.\n'
}

build_target() {
  case "$1" in
    android)
      build_android
      ;;
    flatpak)
      target_supported_on_host flatpak || fail \
        'Flatpak builds require Linux with flatpak-builder and the Flatpak SDK/runtime.'
      build_flatpak
      ;;
    windows)
      build_windows
      ;;
    macos)
      build_macos
      ;;
    all)
      usage >&2
      fail "The all target needs separate native hosts; current host is $(host_name)."
      ;;
    *)
      usage >&2
      fail "Unknown target: $1"
      ;;
  esac
}

cd "$REPO_ROOT"

if [[ "$TARGET" == "-h" || "$TARGET" == "--help" ]]; then
  usage
  exit 0
fi

require_command flutter
require_command dart
check_release_version
check_backend_origin

if [[ "$TARGET" == "all" ]]; then
  usage >&2
  fail "Run android/flatpak on Linux, windows on Windows, and macos on macOS; current host is $(host_name)."
fi

if ! target_supported_on_host "$TARGET"; then
  fail "Target ${TARGET} is not supported by the current host ($(host_name)); use its native host."
fi

run_validation
build_target "$TARGET"

printf 'LEB2 Watch v%s build completed for %s.\n' "$RELEASE_VERSION" "$TARGET"
