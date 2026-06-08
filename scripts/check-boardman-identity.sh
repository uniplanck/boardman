#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Board-Man"
BUNDLE_ID="com.uniplanck.BoardMan"
INSTALL_PATH="/Applications/${APP_NAME}.app"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

print_identity() {
  local app_path="$1"
  echo "Path: $app_path"
  echo "  CFBundleIdentifier: $(plist_value "$app_path" CFBundleIdentifier)"
  echo "  CFBundleName: $(plist_value "$app_path" CFBundleName)"
  echo "  CFBundleDisplayName: $(plist_value "$app_path" CFBundleDisplayName)"
}

echo "Canonical Board-Man identity check"
echo "Expected:"
echo "  Path: ${INSTALL_PATH}"
echo "  CFBundleIdentifier: ${BUNDLE_ID}"
echo "  CFBundleName: ${APP_NAME}"
echo "  CFBundleDisplayName: ${APP_NAME}"
echo ""

if [[ -d "$INSTALL_PATH" ]]; then
  print_identity "$INSTALL_PATH"
else
  echo "Canonical app not found: ${INSTALL_PATH}"
fi

echo ""
echo "Board-Man-like app directories visible in common locations:"
find /Applications "$HOME/Applications" /tmp "${TMPDIR:-/tmp}" \
  -maxdepth 5 \
  -type d \
  \( -name "Board-Man*.app" -o -name "*Dogfood*.app" \) \
  -prune \
  -print 2>/dev/null | sort -u

echo ""
echo "No changes made."
