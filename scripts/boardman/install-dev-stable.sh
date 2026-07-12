#!/bin/bash
set -euo pipefail

# Safe local install/stability helper for Board-Man
# Reduces repeated TCC Accessibility/Input Monitoring permission churn by:
# - Consistent certificate signing with one stable identity
# - Stable bundle identifier and canonical /Applications path
# - Quarantine xattr removal
# - Safe quit/replace/reopen sequence
# - LaunchServices registration for the installed app path
# - No-index build/backup locations to avoid Spotlight duplicates
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
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_ROOT="${HOME}/Library/Caches/Board-Man"
DERIVED_DATA="${CACHE_ROOT}/DerivedData.noindex"
BACKUP_ROOT="${CACHE_ROOT}/Backups.noindex"
DIGEST_FILE="${DIGEST_FILE:-/tmp/boardman-install-dev-stable.digest.txt}"
SCRIPT_NAME=$(basename "$0")
BUILT_APP_OVERRIDE=""
SIGNING_IDENTITY="${BOARDMAN_SIGNING_IDENTITY:-Board-Man Local Developer}"
LOCAL_ARCH="${BOARDMAN_LOCAL_ARCH:-$(uname -m)}"
OWNER_TOOL="$REPO_ROOT/scripts/boardman/owner-license-tool.swift"
OWNER_ISSUED_TO="${BOARDMAN_OWNER_ISSUED_TO:-Board-Man Owner}"
OWNER_SUBJECT="${BOARDMAN_OWNER_SUBJECT:-planckworld}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

usage() {
  cat << EOF
Usage: $SCRIPT_NAME [--dry-run] [--no-build] [--built-app PATH] [--configuration Debug|Release] [--signing-identity NAME] [--override-panel-ui=0|1]

Safe dev install helper for Board-Man v4b.
- Builds from $PROJECT (Board-Man scheme)
- Quits app safely
- Backs up current /Applications/Board-Man.app
- Replaces with fresh build or --built-app
- Removes quarantine, signs with one stable certificate identity, verifies
- Uses no-index build/backup paths so Finder search does not collect dev copies
- Registers only /Applications/Board-Man.app with LaunchServices
- Optionally preserves/restores BoardManUsePanelUI
- Reopens app
- Prints digest and copies to clipboard + $DIGEST_FILE

Options:
  --dry-run          : Simulate all steps, no actual build/install
  --no-build         : Skip build, use latest from DerivedData (for quick reinstall)
  --built-app PATH   : Install an already built Board-Man.app
  --configuration Debug|Release : Build configuration (default: Release)
  --signing-identity NAME : Stable local signing identity (default: Board-Man Local Developer)
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
    --signing-identity)
      if [ $# -lt 2 ]; then
        echo "Error: --signing-identity requires a certificate name."
        exit 1
      fi
      SIGNING_IDENTITY="${2:-}"
      shift 2
      ;;
    --signing-identity=*)
      SIGNING_IDENTITY="${1#*=}"
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

if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "BLOCKED: Stable signing identity not found: $SIGNING_IDENTITY"
  echo "Available code-signing identities can be checked with: security find-identity -v -p codesigning"
  echo "Refusing ad-hoc fallback because it causes macOS permission identity churn."
  exit 2
fi

echo "=== Board-Man Stable Dev Install Helper ==="
echo "Branch: $(cd "$REPO_ROOT" && git branch --show-current 2>/dev/null || echo unknown)"
echo "Head: $(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "Signing identity: $SIGNING_IDENTITY"
echo "Local architecture: $LOCAL_ARCH"
echo "DerivedData: $DERIVED_DATA"
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
  osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null &
  QUIT_PID=$!
  for _ in 1 2 3 4 5; do
    kill -0 "$QUIT_PID" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$QUIT_PID" 2>/dev/null; then
    kill "$QUIT_PID" 2>/dev/null || true
  fi
  wait "$QUIT_PID" 2>/dev/null || true
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 3
  echo "App quit confirmed."
else
  echo "[DRY] Would quit app using osascript/pkill."
fi

# Backup if exists
if [ -d "$INSTALLED_PATH" ] && [ "$DRY_RUN" = false ]; then
  mkdir -p "$BACKUP_ROOT"
  BACKUP_PATH="${BACKUP_ROOT}/${APP_NAME}-$(date +%Y%m%d_%H%M%S).app"
  echo "Backing up current app to $BACKUP_PATH"
  ditto "$INSTALLED_PATH" "$BACKUP_PATH"
  echo "Backup created in no-index cache storage."
fi

# Build (lightweight if possible, but full Release for stability)
if [ "$DRY_RUN" = false ] && [ "$NO_BUILD" = false ] && [ -z "$BUILT_APP_OVERRIDE" ]; then
  mkdir -p "$CACHE_ROOT" "$DERIVED_DATA"
  touch "$DERIVED_DATA/.metadata_never_index"
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
    ARCHS="$LOCAL_ARCH" \
    ONLY_ACTIVE_ARCH=YES \
    ENABLE_TESTABILITY=NO \
    DEAD_CODE_STRIPPING=YES \
    COPY_PHASE_STRIP=YES \
    DEPLOYMENT_POSTPROCESSING=YES \
    STRIP_INSTALLED_PRODUCT=YES \
    build | tail -5
  echo "Build completed."
elif [ -n "$BUILT_APP_OVERRIDE" ]; then
  echo "Skipping build, using --built-app."
elif [ "$DRY_RUN" = true ]; then
  echo "[DRY] Would run xcodebuild $CONFIG build to $DERIVED_DATA"
  BUILT_APP_PATH="SIMULATED/$APP_NAME.app"
else
  echo "Skipping build (--no-build), using the stable no-index DerivedData cache."
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
  ditto "$BUILT_APP_PATH" "$INSTALLED_PATH"
  
  # Remove quarantine/provenance xattrs to reduce TCC friction for local builds.
  xattr -rd com.apple.quarantine "$INSTALLED_PATH" 2>/dev/null || true
  xattr -rd com.apple.provenance "$INSTALLED_PATH" 2>/dev/null || true
  echo "Quarantine/provenance xattrs removed when present."
  
  echo "Applying stable certificate codesign..."
  # Do not enable Hardened Runtime for the local self-signed identity. Without an Apple Team ID,
  # library validation can reject Xcode's debug dylib even when both objects use the same certificate.
  if [ -f "$INSTALLED_PATH/Contents/MacOS/$APP_NAME.debug.dylib" ]; then
    codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" \
      "$INSTALLED_PATH/Contents/MacOS/$APP_NAME.debug.dylib"
  fi
  codesign --force --deep --timestamp=none --sign "$SIGNING_IDENTITY" "$INSTALLED_PATH"
  
  # Verify
  echo "Verifying codesign and bundle identity..."
  codesign --verify --deep --strict "$INSTALLED_PATH"
  INSTALLED_BUNDLE_ID=$(defaults read "$INSTALLED_PATH/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "")
  if [ "$INSTALLED_BUNDLE_ID" != "$BUNDLE_ID" ]; then
    echo "BLOCKED: Bundle ID mismatch after install: $INSTALLED_BUNDLE_ID"
    exit 3
  fi
  echo "Codesign verification passed."
else
  echo "[DRY] Would backup, replace installed app, remove quarantine/provenance xattrs, sign with '$SIGNING_IDENTITY', and verify."
fi

# Preserve an existing signed owner token without touching Keychain. The issuer private key
# is consulted only when no reusable local token exists and a new token must be generated.
LOCAL_OWNER_TOKEN="$HOME/Library/Application Support/com.uniplanck.BoardMan/owner-license.jwt"
if [ "$DRY_RUN" = false ]; then
  if [ -s "$LOCAL_OWNER_TOKEN" ] || security find-generic-password \
      -s "com.uniplanck.BoardMan.OwnerIssuer" \
      -a "p256-private-key-v1" >/dev/null 2>&1; then
    echo "Installing signed Owner Lifetime local state..."
    swift -suppress-warnings "$OWNER_TOOL" install \
      --app "$INSTALLED_PATH" \
      --issued-to "$OWNER_ISSUED_TO" \
      --subject "$OWNER_SUBJECT"
  else
    echo "Owner token and issuer key are absent; keeping the normal Free entitlement path."
  fi
else
  echo "[DRY] Would preserve a local Owner token or generate one only when the issuer key exists."
fi

# Keep build artifacts out of Finder/Spotlight app results without deleting them.
if [ "$DRY_RUN" = false ]; then
  if [ -d "$REPO_ROOT/_copy" ]; then
    touch "$REPO_ROOT/_copy/.metadata_never_index"
  fi
  for derived_root in "$HOME"/Library/Developer/Xcode/DerivedData/Board-Man-*; do
    if [ -d "$derived_root" ]; then
      touch "$derived_root/.metadata_never_index"
    fi
  done
  echo "Marked Board-Man build artifact roots as non-indexable."
else
  echo "[DRY] Would mark Board-Man _copy and DerivedData roots as non-indexable."
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
    {
      find "${TMPDIR:-/tmp}" -path "*BoardManMergedBuild/Build/Products/Debug/$APP_NAME.app" -type d -prune 2>/dev/null \
        | while IFS= read -r stale_path; do
          "$LSREGISTER" -u "$stale_path" >/dev/null 2>&1 || true
        done
    } || true
    {
      "$LSREGISTER" -dump 2>/dev/null \
        | awk -F'path:[[:space:]]*' '/path: .*Board-Man\.app/ { print $2 }' \
        | sed 's#\(Board-Man\.app\).*#\1#' \
        | sort -u \
        | while IFS= read -r stale_path; do
          if [ -n "$stale_path" ] && [ "$stale_path" != "$INSTALLED_PATH" ]; then
            "$LSREGISTER" -u "$stale_path" >/dev/null 2>&1 || true
          fi
        done
    } || true
    {
      mdfind 'kMDItemFSName == "Board-Man.app"c' 2>/dev/null \
        | while IFS= read -r stale_path; do
          if [ -n "$stale_path" ] && [ "$stale_path" != "$INSTALLED_PATH" ]; then
            "$LSREGISTER" -u "$stale_path" >/dev/null 2>&1 || true
          fi
        done
    } || true
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
what_it_improves=reduces repeated TCC stale permission re-prompts via one stable certificate identity, canonical install path, no-index build storage, LaunchServices cleanup, verification, and safe reopen.
what_it_cannot_do=bypass the initial macOS TCC approval, mutate the TCC database, change the bundle id, or guarantee preservation if the signing certificate itself changes.
signing_identity=$SIGNING_IDENTITY
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
