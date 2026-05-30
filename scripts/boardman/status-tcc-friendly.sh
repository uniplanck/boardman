#!/bin/bash
set -euo pipefail

APP_NAME="Board-Man"
INSTALLED_PATH="/Applications/${APP_NAME}.app"
BUNDLE_ID="com.uniplanck.BoardMan"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== Board-Man TCC-Friendly Status Helper ==="
echo "Purpose: Diagnose install state without mutating TCC, permissions, or app state."
echo ""

if [ ! -d "$INSTALLED_PATH" ]; then
  echo "ERROR: Installed app not found at $INSTALLED_PATH"
  exit 1
fi

echo "Installed App:"
echo "  Path: $INSTALLED_PATH"
echo "  Bundle ID: $(plutil -extract CFBundleIdentifier raw -o - "$INSTALLED_PATH/Contents/Info.plist" 2>/dev/null || echo "$BUNDLE_ID")"
echo "  Name: $(plutil -extract CFBundleName raw -o - "$INSTALLED_PATH/Contents/Info.plist" 2>/dev/null || echo "$APP_NAME")"
echo "  Executable: $INSTALLED_PATH/Contents/MacOS/$(plutil -extract CFBundleExecutable raw -o - "$INSTALLED_PATH/Contents/Info.plist" 2>/dev/null | tr -d '"' || echo "Board-Man")"

echo -n "  Codesign Verify: "
if codesign --verify --deep --strict "$INSTALLED_PATH" >/dev/null 2>&1; then
  echo "OK (rc=0)"
else
  echo "FAILED"
  codesign --verify --deep --strict "$INSTALLED_PATH" 2>&1 || true
fi

UI_VALUE=$(defaults read "$BUNDLE_ID" BoardManUsePanelUI 2>/dev/null || echo "not set (defaults to 1)")
echo "  BoardManUsePanelUI: $UI_VALUE"

RUNNING_PIDS=$(pgrep -x "$APP_NAME" || echo "")
if [ -n "$RUNNING_PIDS" ]; then
  echo "  Running Process: YES (PIDs: $RUNNING_PIDS)"
else
  echo "  Running Process: NO"
fi

echo ""
echo "Spotlight Duplicates (potential TCC confusion sources):"
DUPLICATES=$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | grep -v "^${INSTALLED_PATH}\$" | head -10 || echo "none found")
if [ "$DUPLICATES" = "none found" ]; then
  echo "  $DUPLICATES"
else
  echo "$DUPLICATES" | sed 's/^/  - /'
  echo "  (Note: Multiple copies can cause TCC permission conflicts on macOS)"
fi

echo ""
echo "TCC Reminder (no changes made):"
echo "  macOS TCC permissions are tied to the app's codesign identity and path."
echo "  This helper cannot bypass or automate the initial TCC grant dialogs."
echo "  Manually approve Accessibility and Input Monitoring in System Settings if prompted."
echo ""
echo "Current git head: $(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
echo "=== End of Status ==="
