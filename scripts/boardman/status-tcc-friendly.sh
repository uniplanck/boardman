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
echo "  Bundle ID: $(plutil -extract CFBundleIdentifier raw -o - \"$INSTALLED_PATH/Contents/Info.plist\" 2>/dev/null || echo \"$BUNDLE_ID\")"
echo "  Name: $(plutil -extract CFBundleName raw -o - \"$INSTALLED_PATH/Contents/Info.plist\" 2>/dev/null || echo \"$APP_NAME\")"
EXECUTABLE_NAME=$(plutil -extract CFBundleExecutable raw -o - "$INSTALLED_PATH/Contents/Info.plist" 2>/dev/null | tr -d '"' || echo "Board-Man")
EXECUTABLE_PATH="$INSTALLED_PATH/Contents/MacOS/$EXECUTABLE_NAME"
echo "  Executable: $EXECUTABLE_PATH"
echo "  App Size: $(du -sh "$INSTALLED_PATH" | awk '{print $1}')"
echo "  Architecture: $(file "$EXECUTABLE_PATH" | sed 's/.*: //')"

echo -n "  Codesign Verify: "
if codesign --verify --deep --strict "$INSTALLED_PATH" >/dev/null 2>&1; then
  echo "OK (rc=0)"
else
  echo "FAILED"
  codesign --verify --deep --strict "$INSTALLED_PATH" 2>&1 || true
fi
SIGNATURE_SUMMARY=$(codesign -dv --verbose=4 "$INSTALLED_PATH" 2>&1 | grep -E "^(Authority|Signature|TeamIdentifier|Identifier)=" || true)
if [ -n "$SIGNATURE_SUMMARY" ]; then
  echo "$SIGNATURE_SUMMARY" | sed 's/^/  /'
fi
if codesign -dv --verbose=4 "$INSTALLED_PATH" 2>&1 | grep -q '^Signature=adhoc$'; then
  echo "  TCC Identity Risk: HIGH — ad-hoc signature changes across rebuilds"
else
  echo "  TCC Identity Risk: LOW — certificate-signed app"
fi

UI_VALUE=$(defaults read "$BUNDLE_ID" BoardManUsePanelUI 2>/dev/null || echo "not set (defaults to 1)")
echo "  BoardManUsePanelUI: $UI_VALUE"

ENTITLEMENT_STATUS=$(defaults read "$BUNDLE_ID" BoardManDiagnosticEntitlementStatus 2>/dev/null || echo "not checked")
ENTITLEMENT_PLAN=$(defaults read "$BUNDLE_ID" BoardManDiagnosticEntitlementPlan 2>/dev/null || echo "unknown")
echo "  Entitlement Diagnostic: $ENTITLEMENT_STATUS / $ENTITLEMENT_PLAN"
if security find-generic-password -s "com.uniplanck.BoardMan.LicenseToken" -a "signedLicenseToken" >/dev/null 2>&1; then
  echo "  Signed License Token: present in Keychain"
else
  echo "  Signed License Token: missing"
fi

RUNNING_PIDS=$(pgrep -x "$APP_NAME" || echo "")
if [ -n "$RUNNING_PIDS" ]; then
  echo "  Running Process: YES (PIDs: $RUNNING_PIDS)"
else
  echo "  Running Process: NO"
fi

echo ""
echo "Spotlight Duplicates (build artifacts, not separate installs):"
DUPLICATES=$(mdfind 'kMDItemFSName == "Board-Man.app"c' 2>/dev/null | grep -v "^${INSTALLED_PATH}\$" | head -20 || echo "none found")
if [ "$DUPLICATES" = "none found" ]; then
  echo "  $DUPLICATES"
else
  echo "$DUPLICATES" | sed 's/^/  - /'
  echo "  (These should be excluded from Spotlight and unregistered from LaunchServices.)"
fi

echo ""
echo "TCC Reminder (no changes made):"
echo "  macOS TCC (Accessibility / Input Monitoring) permissions are tied to the app's code requirement and path."
echo "  The stable installer uses one certificate identity, one bundle id, and /Applications/Board-Man.app."
echo "  It CANNOT bypass or automate the initial TCC grant dialogs. You must manually approve in"
echo "  System Settings > Privacy & Security if prompted after install/rebuild."
echo "  For repeated issues: remove app from TCC lists manually via System Settings (or reset via Privacy & Security UI), then reinstall with this helper."
echo ""
echo "Current git head: $(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo 'ea6ae8b')"
echo "=== End of Status ==="
