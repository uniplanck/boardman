#!/bin/bash
set -euo pipefail

APP_NAME="Board-Man"
CANONICAL_APP="/Applications/${APP_NAME}.app"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COPY_ROOT="$REPO_ROOT/_copy"
CACHE_ROOT="$HOME/Library/Caches/Board-Man"
DERIVED_ARCHIVE="$CACHE_ROOT/DerivedDataArchive.noindex"
COPY_ARCHIVE="$COPY_ROOT/build-artifacts.noindex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
DRY_RUN=false

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
elif [ $# -gt 0 ]; then
  echo "Usage: $(basename "$0") [--dry-run]"
  exit 1
fi

archive_directory() {
  local source="$1"
  local destination_root="$2"
  local base destination
  base=$(basename "$source")
  destination="$destination_root/$base"
  if [ -e "$destination" ]; then
    destination="$destination_root/${base}-$(date +%Y%m%d_%H%M%S)"
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY] $source -> $destination"
    return
  fi

  mkdir -p "$destination_root"
  mv "$source" "$destination"
  echo "Archived: $source -> $destination"
}

unregister_apps_below() {
  local root="$1"
  [ -x "$LSREGISTER" ] || return 0
  [ -d "$root" ] || return 0

  while IFS= read -r app_path; do
    if [ "$app_path" != "$CANONICAL_APP" ]; then
      "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
    fi
  done < <(find "$root" -type d -name "${APP_NAME}.app" -prune 2>/dev/null || true)
}

neutralize_archived_app_bundles() {
  local root="$1"
  [ -d "$root" ] || return 0

  while IFS= read -r app_path; do
    local archived_path
    archived_path="$(dirname "$app_path")/.archived-app-bundle.payload"
    if [ "$DRY_RUN" = true ]; then
      echo "[DRY] $app_path -> $archived_path"
    elif [ ! -e "$archived_path" ]; then
      mv "$app_path" "$archived_path"
      echo "Archived app bundle payload: $archived_path"
    fi
  done < <(find "$root" -type d \( -name "${APP_NAME}.app" -o -name "${APP_NAME}.app.archive" \) -prune 2>/dev/null || true)
}

echo "=== Board-Man Local Build Copy Archive ==="
echo "Canonical app preserved: $CANONICAL_APP"

# Archive old Xcode-derived Board-Man build roots. Future builds use
# ~/Library/Caches/Board-Man/DerivedData.noindex instead.
for derived_root in "$HOME"/Library/Developer/Xcode/DerivedData/Board-Man-*; do
  [ -d "$derived_root" ] || continue
  unregister_apps_below "$derived_root"
  archive_directory "$derived_root" "$DERIVED_ARCHIVE"
done

# Archive only top-level _copy entries that actually contain Board-Man.app.
if [ -d "$COPY_ROOT" ]; then
  if [ "$DRY_RUN" = false ]; then
    mkdir -p "$COPY_ARCHIVE"
    touch "$COPY_ROOT/.metadata_never_index" "$COPY_ARCHIVE/.metadata_never_index"
  fi
  while IFS= read -r entry; do
    [ "$entry" = "$COPY_ARCHIVE" ] && continue
    if find "$entry" -type d -name "${APP_NAME}.app" -print -quit 2>/dev/null | grep -q .; then
      unregister_apps_below "$entry"
      archive_directory "$entry" "$COPY_ARCHIVE"
    fi
  done < <(find "$COPY_ROOT" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null || true)
fi

neutralize_archived_app_bundles "$DERIVED_ARCHIVE"
neutralize_archived_app_bundles "$COPY_ARCHIVE"

if [ "$DRY_RUN" = false ]; then
  mkdir -p "$DERIVED_ARCHIVE"
  touch "$DERIVED_ARCHIVE/.metadata_never_index"
  "$LSREGISTER" -f "$CANONICAL_APP" >/dev/null 2>&1 || true
fi

echo "No files were deleted. Old build artifacts remain under .noindex archives."
echo "=== End ==="
