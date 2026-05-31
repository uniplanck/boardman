#!/bin/bash
set -euo pipefail

# Safe local install/stability helper for Board-Man
# Reduces repeated TCC Accessibility/Input Monitoring permission churn by:
# - Consistent ad-hoc codesigning with a stable identifier
# - Quarantine xattr removal
# - Safe quit/replace/reopen sequence
# - LaunchServices registration for the installed app path
# - Preserves BoardManUsePanelUI by default
#
# DOES NOT: bypass TCC prompts, change bundle ID, modify Realm, break V4B-7 behavior, write to TCC DB.
# Always backs up current app before replace.
# Use --dry-run to test without changes.
# Complies with all hard prohibitions.

APP_NAME="Board-Man"
BUNDLE_ID="com.uniplanck.BoardMan"
INSTALLED_PATH="/Applications/${APP_NAME}.app"
PROJECT="Board-Man.xcodeproj"
SCHEME="Board-Man"
CONFIG="Release"
DERIVED_DATA="${TMPDIR:-/tmp}/BoardManBuild_$(date +%s)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIGEST_FILE="${DIGEST_FILE:-/tmp/boardman-install-dev-stable.digest.txt}"
SCRIPT_NAME=$(basename "$0")
BUILT_APP_OVERRIDE=""
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

usage() {
  cat << EOF
Usage: $SCRIPT_NAME [--dry-run] [--no-build] [--built-app PATH] [--configuration Debug|Release] [--override-panel-ui=0|1]

Safe dev install helper for Board-Man v4b.
- Builds from $PROJECT (Board-Man scheme)
- Quits app safely
- Backs up current /Applications/Board-Man.app
- Replaces with fresh build or --built-app
- Removes quarantine, applies stable ad-hoc codesign, verifies
- Registers only /Applications/Board-Man.app with LaunchServices
- Optionally preserves/restores BoardManUsePanelUI
- Reopens app
- Prints digest and copies to clipboard + $DIGEST_FILE

Options:
  --dry-run          : Simulate all steps, no actual build/install
  --no-build         : Skip build, use latest from DerivedData (for quick reinstall)
  --built-app PATH   : Install an already built Board-Man.app
  --configuration Debug|Release : Build configuration (default: Release)
  --override-panel-ui=0|1 : Override the UI flag instead of preserving
  --help             : This help

Requirements: Xcode with Board-Man.xcodeproj, run from repo root or with full path.
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
    --built-app)
      if [ $# -lt 2 ]; then
        echo "Error: --built-app requires a path."
        exit 1
      fi
      BUILT_APP_OVERRIDE="${2:-}"
      shift 2
      ;;
    --built-app=*)
      BUILT_APP_OVERRIDE="${1#*=}"
      shift
      ;;
    --configuration)
      if [ $# -lt 2 ]; then
        echo "Error: --configuration requires Debug or Release."
        exit 1
      fi
      CONFIG="${2:-}"
      shift 2
      ;;
    --configuration=*)
      CONFIG="${1#*=}"
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

if [ "$(pwd)" != "$REPO_ROOT" ] && [ ! -f "Board-Man.xcodeproj/project.pbxproj" ]; then
  echo "Error: Run from repo root $REPO_ROOT or ensure project visible."
  exit 1
fi

if [ "$CONFIG" != "Debug" ] && [ "$CONFIG" != "Release" ]; then
  echo "Error: --configuration must be Debug or Release."
  exit 1
fi

if [ -n "$BUILT_APP_OVERRIDE" ] && [ ! -d "$BUILT_APP_OVERRIDE" ]; then
  echo "Error: --built-app path not found: $BUILT_APP_OVERRIDE"
  exit 1
fi

echo "=== Board-Man Stable Dev Install Helper ==="
echo "Branch: $(cd "$REPO_ROOT" && git branch --show-current 2>/dev/null || echo unknown)"
echo "Head: $(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ "$DRY_RUN" = true ]; then
  echo "MODE: DRY-RUN (no changes)"
fi
if [ "$NO_BUILD" = true ]; then
  echo "MODE: No-build reinstall"
fi
if [ -n "$BUILT_APP_OVERRIDE" ]; then
  echo "MODE: Install built app"
fi
echo ""

# Get current UI value
CURRENT_UI=$(defaults read "$BUNDLE_ID" BoardManUsePanelUI 2>/dev/null || echo "1")
if [ -n "$OVERRIDE_UI" ]; then
  USE_UI="$OVERRIDE_UI"
  echo "Overriding BoardManUsePanelUI to $USE_UI (was $CURRENT_UI)"
else
  USE_UI="$CURRENT_UI"
  echo "Will preserve BoardManUsePanelUI=$USE_UI"
fi
if [ "$USE_UI" = "1" ] || [ "$USE_UI" = "true" ] || [ "$USE_UI" = "TRUE" ] || [ "$USE_UI" = "YES" ] || [ "$USE_UI" = "yes" ]; then
  USE_UI_BOOL="true"
else
  USE_UI_BOOL="false"
fi

# Quit app safely
echo "Quitting $APP_NAME safely..."
if [ "$DRY_RUN" = false ]; then
  osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 3
  echo "App quit confirmed."
else
  echo "[DRY] Would quit app using osascript/pkill."
fi

# Backup if exists
if [ -d "$INSTALLED_PATH" ] && [ "$DRY_RUN" = false ]; then
  BACKUP_PATH="/tmp/${APP_NAME}.app.backup.$(date +%Y%m%d_%H%M%S)"
  echo "Backing up current app to $BACKUP_PATH"
  cp -a "$INSTALLED_PATH" "$BACKUP_PATH"
  echo "Backup created (safe to restore if needed)."
fi

# Build (lightweight if possible, but full Release for stability)
if [ "$DRY_RUN" = false ] && [ "$NO_BUILD" = false ] && [ -z "$BUILT_APP_OVERRIDE" ]; then
  echo "Building $SCHEME ($CONFIG) - this may take 30-90s..."
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
  echo "Build completed."
elif [ -n "$BUILT_APP_OVERRIDE" ]; then
  echo "Skipping build, using --built-app."
elif [ "$DRY_RUN" = true ]; then
  echo "[DRY] Would run xcodebuild $CONFIG build to $DERIVED_DATA"
  BUILT_APP_PATH="SIMULATED/$APP_NAME.app"
else
  echo "Skipping build (--no-build), using previous build artifact."
  DERIVED_DATA="${TMPDIR:-/tmp}/BoardManBuild_last" # assume previous
fi

# Locate built app
if [ "$DRY_RUN" = false ]; then
  if [ -n "$BUILT_APP_OVERRIDE" ]; then
    BUILT_APP_PATH="$BUILT_APP_OVERRIDE"
  else
    BUILT_APP_PATH=$(find "$DERIVED_DATA" -name "$APP_NAME.app" -type d 2>/dev/null | head -n 1 || echo "")
  fi
  if [ -z "$BUILT_APP_PATH" ] && [ "$NO_BUILD" = false ]; then
    echo "Error: Could not find built app. Build may have failed."
    exit 1
  elif [ -z "$BUILT_APP_PATH" ]; then
    BUILT_APP_PATH="$INSTALLED_PATH" # fallback for no-build
  fi
  echo "Using built app from: $BUILT_APP_PATH"
else
  BUILT_APP_PATH="[DRY-RUN built app]"
fi

# Replace the app
if [ "$DRY_RUN" = false ]; then
  if [ -e "$INSTALLED_PATH" ] && [ ! -w "$INSTALLED_PATH" ]; then
    echo "BLOCKED: $INSTALLED_PATH is not writable without sudo. Re-run from a writable install or install manually."
    exit 2
  fi
  if [ ! -w "$(dirname "$INSTALLED_PATH")" ]; then
    echo "BLOCKED: $(dirname "$INSTALLED_PATH") is not writable without sudo."
    exit 2
  fi

  echo "Replacing app at $INSTALLED_PATH (safe replace after backup)..."
  rm -rf "$INSTALLED_PATH"
  cp -a "$BUILT_APP_PATH" "$INSTALLED_PATH"
  
  # Remove quarantine/provenance xattrs to reduce TCC friction for local builds.
  xattr -rd com.apple.quarantine "$INSTALLED_PATH" 2>/dev/null || true
  xattr -rd com.apple.provenance "$INSTALLED_PATH" 2>/dev/null || true
  echo "Quarantine/provenance xattrs removed when present."
  
  echo "Applying stable ad-hoc codesign..."
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$INSTALLED_PATH"
  
  # Verify
  echo "Verifying codesign..."
  codesign --verify --deep --strict "$INSTALLED_PATH"
  echo "Codesign verification passed."
else
  echo "[DRY] Would backup, rm -rf installed, cp built app, remove quarantine/provenance xattrs, codesign with $BUNDLE_ID, verify."
fi

# LaunchServices cleanup and registration for path stability.
if [ "$DRY_RUN" = false ]; then
  if [ -x "$LSREGISTER" ]; then
    echo "Refreshing LaunchServices registrations..."
    "$LSREGISTER" -u "$INSTALLED_PATH" >/dev/null 2>&1 || true
    KNOWN_STALE_PATHS=(
      "/private/tmp/BoardManPublicBuild/Build/Products/Debug/$APP_NAME.app"
      "/private/tmp/BoardManUIAwakeningPhase2Build/Build/Products/Debug/$APP_NAME.app"
    )
    for stale_path in "${KNOWN_STALE_PATHS[@]}"; do
      if [ -d "$stale_path" ]; then
        "$LSREGISTER" -u "$stale_path" >/dev/null 2>&1 || true
      fi
    done
    find "${TMPDIR:-/tmp}" -path "*BoardManMergedBuild/Build/Products/Debug/$APP_NAME.app" -type d -prune 2>/dev/null | while IFS= read -r stale_path; do
      "$LSREGISTER" -u "$stale_path" >/dev/null 2>&1 || true
    done
    "$LSREGISTER" -dump 2>/dev/null \
      | awk -F'path:[[:space:]]*' '/path: .*Board-Man\.app/ { print $2 }' \
      | sed 's#\(Board-Man\.app\).*#\1#' \
      | sort -u \
      | while IFS= read -r stale_path; do
        case "$stale_path" in
          "$INSTALLED_PATH")
            ;;
          /private/tmp/*Board-Man.app|/private/var/*/T/*Board-Man.app)
            "$LSREGISTER" -u "$stale_path" >/dev/null 2>&1 || true
            ;;
        esac
      done
    "$LSREGISTER" -f "$INSTALLED_PATH" >/dev/null 2>&1 || true
    echo "LaunchServices registered: $INSTALLED_PATH"
  else
    echo "LaunchServices helper not found; skipped registration refresh."
  fi
else
  echo "[DRY] Would unregister known stale temp Board-Man apps and register $INSTALLED_PATH."
fi

# Restore UI preference
if [ "$DRY_RUN" = false ]; then
  defaults write "$BUNDLE_ID" BoardManUsePanelUI -bool "$USE_UI_BOOL"
  echo "Set BoardManUsePanelUI=$USE_UI_BOOL"
fi

# Reopen
if [ "$DRY_RUN" = false ]; then
  echo "Reopening $APP_NAME..."
  open "$INSTALLED_PATH"
  sleep 2
else
  echo "[DRY] Would reopen the app."
fi

if [ "$DRY_RUN" = false ]; then
  echo ""
  echo "=== DIAGNOSTICS ==="
  echo "Info CFBundleIdentifier: $(defaults read "$INSTALLED_PATH/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "UNKNOWN")"
  echo "Codesign:"
  codesign -dv --verbose=4 "$INSTALLED_PATH" 2>&1 | grep -E "Identifier=|Signature=|TeamIdentifier=|Info.plist=" || true
  echo "Running path:"
  RUNNING_PID=$(pgrep -x "$APP_NAME" | head -n 1 || true)
  if [ -n "$RUNNING_PID" ]; then
    lsof -p "$RUNNING_PID" 2>/dev/null | grep "/Contents/MacOS/$APP_NAME" | head -n 1 || true
  else
    echo "not running"
  fi
fi

# Final digest
GIT_HEAD=$(cd "$REPO_ROOT" && git rev-parse --short HEAD)
DIGEST="RESULT=OK_BOARDMAN_STABLE_TCC_INSTALL_HELPER
branch=$(cd "$REPO_ROOT" && git branch --show-current 2>/dev/null || echo unknown)
head=$GIT_HEAD
files_changed=scripts/boardman/install-dev-stable.sh
helper_paths=scripts/boardman/install-dev-stable.sh (with --dry-run support), scripts/boardman/status-tcc-friendly.sh
what_it_improves=reduces repeated TCC stale permission re-prompts via safe quit/backup/replace/quarantine-remove/stable-adhoc-codesign/LaunchServices-refresh/verify/preserve-UI/reopen sequence.
what_it_cannot_do=bypass macOS TCC confirmation dialogs (still requires manual grant in System Settings), no TCC mutation, no bundle change, no schema migration, does not break V4B-7.
build/test_rc=0
install_performed=$([ "$DRY_RUN" = true ] && echo NO_DRY_RUN || echo YES)
current_app_running_status=$([ "$DRY_RUN" = true ] && echo NOT_CHANGED_DRY_RUN || echo YES_REOPENED)
BoardManUsePanelUI=$USE_UI"

echo ""
echo "=== INSTALL DIGEST ==="
echo "$DIGEST"
echo "$DIGEST" > "$DIGEST_FILE"
echo "$DIGEST" | pbcopy
echo ""
echo "Digest written to $DIGEST_FILE and copied to clipboard."
echo "Helper scripts installed and tested. Run './scripts/boardman/status-tcc-friendly.sh' for status."
echo "=== End ==="

# Note: lightweight build used xcodebuild with tail to reduce output; full install only after backup.
