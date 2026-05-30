#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Board-Man"
BUNDLE_ID="com.uniplanck.BoardMan"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$REPO_ROOT/Board-Man.xcodeproj"
SCHEME="Board-Man"
CONFIGURATION="Debug"
DERIVED_DATA="${TMPDIR:-/tmp}/BoardManLocalQA"
INSTALLED_APP="/Applications/${APP_NAME}.app"
BOARDMAN_DIGEST="${BOARDMAN_DIGEST_OUT:-/tmp/boardman-local-qa.digest.txt}"

run_build=true

usage() {
  cat <<EOF
Usage: $(basename "$0") [--no-build]

Runs local Board-Man QA without reading clipboard contents, resetting TCC,
changing permissions, or installing/replacing the app.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      run_build=false
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

timestamp="$(date +%Y%m%d_%H%M%S)"
status="OK"
build_result="SKIPPED"
built_app="unavailable"
installed_app="NO"
codesign_result="SKIPPED"
accessibility_check="MANUAL_CHECK_REQUIRED"
input_monitoring_check="MANUAL_CHECK_REQUIRED"

if [[ "$run_build" == true ]]; then
  rm -rf "$DERIVED_DATA"
  if xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination 'generic/platform=macOS' \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null; then
    build_result="OK"
  else
    build_result="FAILED"
    status="FAILED"
  fi

  built_app="$(find "$DERIVED_DATA" -name "${APP_NAME}.app" -type d 2>/dev/null | head -n 1 || true)"
  if [[ -z "$built_app" ]]; then
    built_app="NOT_FOUND"
    status="FAILED"
  fi
fi

if [[ -d "$INSTALLED_APP" ]]; then
  installed_app="YES"
  if codesign --verify --deep --strict "$INSTALLED_APP" >/dev/null 2>&1; then
    codesign_result="OK"
  else
    codesign_result="FAILED"
    status="FAILED"
  fi
else
  status="FAILED"
fi

if command -v tccutil >/dev/null 2>&1; then
  accessibility_check="OPEN_SYSTEM_SETTINGS_PRIVACY_ACCESSIBILITY"
  input_monitoring_check="OPEN_SYSTEM_SETTINGS_PRIVACY_INPUT_MONITORING"
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

{
  echo "RESULT=BOARDMAN_LOCAL_QA"
  echo "STATUS=$status"
  echo "TIMESTAMP=$timestamp"
  echo "BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
  echo "HEAD=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  echo "BUILD_SMOKE=$build_result"
  echo "BUILT_APP=$built_app"
  echo "INSTALLED_APP=$installed_app"
  echo "INSTALLED_APP_PATH=$INSTALLED_APP"
  echo "CODESIGN_VERIFY=$codesign_result"
  echo "ACCESSIBILITY_STATUS=$accessibility_check"
  echo "INPUT_MONITORING_STATUS=$input_monitoring_check"
  echo "TCC_RESET=NO"
  echo "CLIPBOARD_CONTENT_LOGGED=NO"
  echo "NEXT=If permissions are not active, inspect System Settings manually; this script does not mutate TCC."
} > "$tmp"

cp "$tmp" "$BOARDMAN_DIGEST"
cat "$tmp"

if [[ "$status" != "OK" ]]; then
  exit 1
fi
