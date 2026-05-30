#!/bin/bash
set -euo pipefail

APP_NAME="Board-Man"
BUNDLE_ID="com.uniplanck.BoardMan"
INSTALLED_PATH="/Applications/${APP_NAME}.app"
PROJECT="Board-Man.xcodeproj"
SCHEME="Board-Man"
CONFIG="Release"
DERIVED_DATA="${TMPDIR:-/tmp}/BoardManBuild_$(date +%s)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIGEST_FILE="${BOARDMAN_INSTALL_DIGEST:-/tmp/boardman-install.digest.txt}"
SCRIPT_NAME=$(basename "$0")

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--dry-run] [--no-build] [--override-panel-ui=0|1]

Safe dev install helper for Board-Man.
- Builds from $PROJECT with the Board-Man scheme.
- Quits app safely.
- Backs up current /Applications/Board-Man.app.
- Replaces with fresh build.
- Removes quarantine, applies ad-hoc codesign, verifies.
- Optionally preserves/restores BoardManUsePanelUI.
- Reopens app.

Options:
  --dry-run          Simulate all steps, no actual build/install.
  --no-build         Skip build, use latest from DerivedData.
  --override-panel-ui=0|1
  --help
EOF
  exit 0
}

DRY_RUN=false
NO_BUILD=false
OVERRIDE_UI=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-build)
      NO_BUILD=true
      shift
      ;;
    --override-panel-ui=*)
      OVERRIDE_UI="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [ ! -f "$REPO_ROOT/$PROJECT/project.pbxproj" ]; then
  echo "Error: Board-Man.xcodeproj not found next to this script."
  exit 1
fi

echo "=== Board-Man Stable Dev Install Helper ==="
echo "Repo: $REPO_ROOT"
if [ "$DRY_RUN" = true ]; then
  echo "MODE: DRY-RUN (no changes)"
fi
if [ "$NO_BUILD" = true ]; then
  echo "MODE: No-build reinstall"
fi
echo ""

CURRENT_UI=$(defaults read "$BUNDLE_ID" BoardManUsePanelUI 2>/dev/null || echo "1")
if [ -n "$OVERRIDE_UI" ]; then
  USE_UI="$OVERRIDE_UI"
  echo "Overriding BoardManUsePanelUI to $USE_UI (was $CURRENT_UI)"
else
  USE_UI="$CURRENT_UI"
  echo "Will preserve BoardManUsePanelUI=$USE_UI"
fi

echo "Quitting $APP_NAME safely..."
if [ "$DRY_RUN" = false ]; then
  osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 3
else
  echo "[DRY] Would quit app using osascript/pkill."
fi

if [ -d "$INSTALLED_PATH" ] && [ "$DRY_RUN" = false ]; then
  BACKUP_PATH="/tmp/${APP_NAME}.app.backup.$(date +%Y%m%d_%H%M%S)"
  echo "Backing up current app to $BACKUP_PATH"
  cp -a "$INSTALLED_PATH" "$BACKUP_PATH"
fi

if [ "$DRY_RUN" = false ] && [ "$NO_BUILD" = false ]; then
  echo "Building $SCHEME (Release)..."
  xcodebuild -project "$REPO_ROOT/$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    ENABLE_TESTABILITY=NO \
    build | tail -5
elif [ "$DRY_RUN" = true ]; then
  echo "[DRY] Would run xcodebuild Release build to $DERIVED_DATA"
  BUILT_APP_PATH="SIMULATED/$APP_NAME.app"
else
  echo "Skipping build (--no-build), using previous build artifact."
  DERIVED_DATA="${TMPDIR:-/tmp}/BoardManBuild_last"
fi

if [ "$DRY_RUN" = false ]; then
  BUILT_APP_PATH=$(find "$DERIVED_DATA" -name "$APP_NAME.app" -type d 2>/dev/null | head -n 1 || echo "")
  if [ -z "$BUILT_APP_PATH" ] && [ "$NO_BUILD" = false ]; then
    echo "Error: Could not find built app. Build may have failed."
    exit 1
  elif [ -z "$BUILT_APP_PATH" ]; then
    BUILT_APP_PATH="$INSTALLED_PATH"
  fi
  echo "Using built app from: $BUILT_APP_PATH"
else
  BUILT_APP_PATH="[DRY-RUN built app]"
fi

if [ "$DRY_RUN" = false ]; then
  echo "Replacing app at $INSTALLED_PATH..."
  rm -rf "$INSTALLED_PATH"
  cp -a "$BUILT_APP_PATH" "$INSTALLED_PATH"
  xattr -rd com.apple.quarantine "$INSTALLED_PATH" 2>/dev/null || true
  codesign --force --deep --sign - "$INSTALLED_PATH"
  codesign --verify --deep --strict "$INSTALLED_PATH"
else
  echo "[DRY] Would backup, replace app, remove quarantine, codesign, and verify."
fi

if [ "$DRY_RUN" = false ]; then
  defaults write "$BUNDLE_ID" BoardManUsePanelUI -bool "$USE_UI"
  open -a "$INSTALLED_PATH"
fi

GIT_HEAD=$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
CURRENT_BRANCH=$(cd "$REPO_ROOT" && git branch --show-current 2>/dev/null || echo "unknown")
DIGEST="RESULT=OK_BOARDMAN_DEV_INSTALL
branch=$CURRENT_BRANCH
head=$GIT_HEAD
what_it_improves=safe quit, backup, replace, quarantine removal, ad-hoc codesign, verify, preserve UI setting, reopen
what_it_cannot_do=bypass macOS TCC dialogs or mutate TCC
BoardManUsePanelUI=$USE_UI"

echo ""
echo "=== INSTALL DIGEST ==="
echo "$DIGEST"
echo "$DIGEST" > "$DIGEST_FILE"
echo ""
echo "Digest written to $DIGEST_FILE."
echo "=== End ==="
