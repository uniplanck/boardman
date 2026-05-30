#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="${WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
digest_dir="${BOARDMAN_DIGEST_DIR:-$workspace_root/boardman-digests}"
past_dir="$digest_dir/past"
timestamp="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$past_dir"

result="${RESULT:-BOARDMAN_DIGEST}"
phase="${PHASE:-unknown}"
status="${STATUS:-unknown}"
branch="${BRANCH:-$(git -C "$repo_root" branch --show-current 2>/dev/null || true)}"
pr_url="${PR_URL:-unavailable}"
files_changed="${FILES_CHANGED:-}"
checks="${CHECKS:-}"
next="${NEXT:-}"
blocked_by="${BLOCKED_BY:-}"
ready_to_merge="${READY_TO_MERGE:-NO}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

{
  echo "RESULT=$result"
  echo "PHASE=$phase"
  echo "STATUS=$status"
  echo "BRANCH=$branch"
  echo "PR_URL=$pr_url"
  echo "FILES_CHANGED=$files_changed"
  echo "CHECKS=$checks"
  echo "NEXT=$next"
  echo "BLOCKED_BY=$blocked_by"
  echo "READY_TO_MERGE=$ready_to_merge"
  echo "BOARDMAN_ONLY=YES"
  echo "REPO=$repo_root"
  echo "TIMESTAMP=$timestamp"
} | perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g' > "$tmp"

cp "$tmp" "$workspace_root/boardman.copy.txt"
cp "$tmp" "$workspace_root/copy.txt"
cp "$tmp" "$digest_dir/latest.digest.txt"
cp "$tmp" "$past_dir/$timestamp.digest.txt"

echo "$digest_dir/latest.digest.txt"
