#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Board-Man"
BUNDLE_ID="com.uniplanck.BoardMan"
INSTALL_PATH="/Applications/${APP_NAME}.app"
PROJECT="Board-Man.xcodeproj"
SCHEME="Board-Man"
CONFIGURATION="Release"
RUN_ROOT="_copy/canonical-install-runs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="${REPO_ROOT}/${RUN_ROOT}/${TIMESTAMP}"
DERIVED_DATA="${RUN_DIR}/DerivedData"
DIGEST_FILE="${RUN_DIR}/final.digest.txt"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run]

Build and install the canonical Board-Man app identity:
  Path: ${INSTALL_PATH}
  CFBundleIdentifier: ${BUNDLE_ID}
  CFBundleName: ${APP_NAME}
  CFBundleDisplayName: ${APP_NAME}

This script does not launch, quit, pkill, or reset TCC.
EOF
}

DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 127
  fi
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

assert_identity() {
  local app_path="$1"
  local bundle_id bundle_name display_name
  bundle_id="$(plist_value "$app_path" CFBundleIdentifier)"
  bundle_name="$(plist_value "$app_path" CFBundleName)"
  display_name="$(plist_value "$app_path" CFBundleDisplayName)"

  if [[ "$bundle_id" != "$BUNDLE_ID" ]]; then
    echo "ERROR: unexpected CFBundleIdentifier at $app_path: $bundle_id" >&2
    exit 1
  fi
  if [[ "$bundle_name" != "$APP_NAME" ]]; then
    echo "ERROR: unexpected CFBundleName at $app_path: $bundle_name" >&2
    exit 1
  fi
  if [[ "$display_name" != "$APP_NAME" ]]; then
    echo "ERROR: unexpected CFBundleDisplayName at $app_path: $display_name" >&2
    exit 1
  fi
}

write_digest() {
  local result="$1"
  mkdir -p "$RUN_DIR"
  cat >"$DIGEST_FILE" <<EOF
result=${result}
timestamp=${TIMESTAMP}
branch=$(cd "$REPO_ROOT" && git branch --show-current 2>/dev/null || echo unknown)
head=$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo unknown)
install_path=${INSTALL_PATH}
bundle_id=${BUNDLE_ID}
bundle_name=${APP_NAME}
tcc_reset_run=NO
app_launch_or_quit_run=NO
app_backup_directory_created=NO
backup_format=tar.gz
run_dir=${RUN_DIR}
EOF
}

cleanup_build_products() {
  if [[ -d "$DERIVED_DATA" ]]; then
    rm -rf "$DERIVED_DATA"
  fi
}

trap cleanup_build_products EXIT

require_command xcodebuild
require_command codesign
require_command ditto
require_command tar

cd "$REPO_ROOT"
if [[ ! -f "${PROJECT}/project.pbxproj" ]]; then
  echo "ERROR: project not found: ${REPO_ROOT}/${PROJECT}" >&2
  exit 1
fi

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "ERROR: ${APP_NAME} is running. This script will not quit or kill it." >&2
  echo "Quit ${APP_NAME} manually, then rerun the script if install is intended." >&2
  exit 3
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "DRY RUN: would create ${RUN_DIR}"
  echo "DRY RUN: would build ${SCHEME} ${CONFIGURATION} into ${DERIVED_DATA}"
  echo "DRY RUN: would install only to ${INSTALL_PATH}"
  echo "DRY RUN: would create tar.gz backup only if ${INSTALL_PATH} exists"
  echo "DRY RUN: would ad-hoc sign only ${INSTALL_PATH}"
  write_digest "DRY_RUN"
  echo "Digest: ${DIGEST_FILE}"
  exit 0
fi

mkdir -p "$RUN_DIR"
touch "${REPO_ROOT}/_copy/.metadata_never_index"
touch "${RUN_DIR}/.metadata_never_index"

echo "Building ${SCHEME} ${CONFIGURATION}..."
xcodebuild \
  -project "${REPO_ROOT}/${PROJECT}" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

BUILT_APP="$(find "$DERIVED_DATA/Build/Products/${CONFIGURATION}" -maxdepth 1 -type d -name "${APP_NAME}.app" -print -quit)"
if [[ -z "$BUILT_APP" || ! -d "$BUILT_APP" ]]; then
  echo "ERROR: built app not found under ${DERIVED_DATA}" >&2
  exit 1
fi

assert_identity "$BUILT_APP"

if [[ -d "$INSTALL_PATH" ]]; then
  BACKUP_TGZ="${RUN_DIR}/${APP_NAME}-${TIMESTAMP}.tar.gz"
  echo "Creating tar.gz backup: ${BACKUP_TGZ}"
  tar -czf "$BACKUP_TGZ" -C "/Applications" "${APP_NAME}.app"
fi

echo "Installing canonical app: ${INSTALL_PATH}"
rm -rf "$INSTALL_PATH"
ditto "$BUILT_APP" "$INSTALL_PATH"

assert_identity "$INSTALL_PATH"

echo "Ad-hoc signing canonical installed app..."
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$INSTALL_PATH"
codesign --verify --deep --strict "$INSTALL_PATH"

cleanup_build_products

write_digest "OK"

cat <<EOF
Install digest:
  result: OK
  installed: ${INSTALL_PATH}
  identity: ${BUNDLE_ID} / ${APP_NAME}
  backup: tar.gz only
  tcc reset: not run
  launch/quit: not run
  run dir: ${RUN_DIR}
  digest: ${DIGEST_FILE}
EOF
