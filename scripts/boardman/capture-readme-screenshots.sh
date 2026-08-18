#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_PATH="${BOARDMAN_SCREENSHOT_APP:-/Applications/Board-Man.app}"
OUTPUT_DIR="${BOARDMAN_SCREENSHOT_OUTPUT_DIR:-$REPO_ROOT/docs/assets/screenshots}"
TMP_ROOT="$(mktemp -d /tmp/boardman-readme-screenshots.XXXXXX)"
CANONICAL_APP="/Applications/Board-Man.app"
WAS_RUNNING=false

if [ ! -x "$APP_PATH/Contents/MacOS/Board-Man" ]; then
  echo "Error: Board-Man executable not found at $APP_PATH"
  exit 1
fi

if pgrep -x Board-Man >/dev/null 2>&1; then
  WAS_RUNNING=true
fi

cleanup() {
  pkill -x Board-Man >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
  printf '%s' 'Board-Man screenshots refreshed with safe demo content.' | pbcopy
  if [ "$WAS_RUNNING" = true ] && [ -d "$CANONICAL_APP" ]; then
    open "$CANONICAL_APP" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

mkdir -p "$OUTPUT_DIR"
pkill -x Board-Man >/dev/null 2>&1 || true
sleep 2

seed_clipboard() {
  local language="$1"
  local values=()
  if [ "$language" = "日本語" ]; then
    values=(
      '⌘⌥V でクリップボード履歴をすぐ開く'
      '打ち合わせメモ｜プロダクト公開｜14:30'
      'Board-Manは履歴・定型文・画像をローカルで管理します'
      'デザイン確認：階層・余白・コントラスト・狭幅表示'
      'https://github.com/uniplanck/boardman'
      'git status --short --branch'
      '確認しました。本日中にご連絡します。'
      'リリース前にテスト・署名・更新内容を確認する'
    )
  else
    values=(
      'Open clipboard history instantly with ⌘⌥V'
      'Launch notes · Product update · 14:30'
      'Board-Man keeps history, templates, and images local'
      'Design checklist: hierarchy · spacing · contrast · narrow width'
      'https://github.com/uniplanck/boardman'
      'git status --short --branch'
      'Thanks — I’ll review this today.'
      'Review tests, signing, and release notes before shipping'
    )
  fi

  for value in "${values[@]}"; do
    printf '%s' "$value" | pbcopy
    sleep 0.28
  done
}

start_isolated_app() {
  local profile_name="$1"
  local language="$2"
  local scene="$3"
  local output_path="$4"
  local width="$5"
  local height="$6"
  local profile_root="$TMP_ROOT/$profile_name"
  mkdir -p "$profile_root/Library/Application Support" "$profile_root/Library/Preferences"

  env HOME="$profile_root" CFFIXED_USER_HOME="$profile_root" \
    defaults write com.uniplanck.BoardMan BoardManLanguage -string "$language"
  env HOME="$profile_root" CFFIXED_USER_HOME="$profile_root" \
    defaults write com.uniplanck.BoardMan BoardManPanelHeight -int 820
  env HOME="$profile_root" CFFIXED_USER_HOME="$profile_root" \
    defaults write com.uniplanck.BoardMan BoardManTimestampPosition -string right
  env HOME="$profile_root" CFFIXED_USER_HOME="$profile_root" \
    defaults write com.uniplanck.BoardMan BoardManShowUsageCount -bool true
  env HOME="$profile_root" CFFIXED_USER_HOME="$profile_root" \
    defaults write com.uniplanck.BoardMan BoardManUsePanelUI -bool true
  env HOME="$profile_root" CFFIXED_USER_HOME="$profile_root" \
    defaults write com.uniplanck.BoardMan suppressAlertForLoginItem -bool true

  env HOME="$profile_root" CFFIXED_USER_HOME="$profile_root" \
    BOARDMAN_SCREENSHOT_OUTPUT="$output_path" \
    BOARDMAN_SCREENSHOT_SCENE="$scene" \
    BOARDMAN_SCREENSHOT_WIDTH="$width" \
    BOARDMAN_SCREENSHOT_HEIGHT="$height" \
    BOARDMAN_SCREENSHOT_DELAY="4.5" \
    "$APP_PATH/Contents/MacOS/Board-Man" &
  SCREENSHOT_PID=$!
  sleep 1.2
  seed_clipboard "$language"
}

capture_scene() {
  local profile_name="$1"
  local language="$2"
  local scene="$3"
  local output_name="$4"
  local width="$5"
  local height="$6"

  local output_path="$OUTPUT_DIR/$output_name"
  rm -f "$output_path"
  pkill -x Board-Man >/dev/null 2>&1 || true
  sleep 1
  start_isolated_app "$profile_name" "$language" "$scene" "$output_path" "$width" "$height"

  for _ in $(seq 1 80); do
    if [ -s "$output_path" ]; then break; fi
    sleep 0.25
  done
  if [ ! -s "$output_path" ]; then
    echo "Error: Board-Man did not export $output_name"
    exit 1
  fi
  echo "Captured $output_path"

  kill "$SCREENSHOT_PID" >/dev/null 2>&1 || true
  wait "$SCREENSHOT_PID" >/dev/null 2>&1 || true
  sleep 1
}

capture_scene english-history English history board-man-history-en.png 800 560
capture_scene english-templates English templates board-man-templates-en.png 800 760
capture_scene english-settings English settings board-man-settings-en.png 800 820
capture_scene english-compact English history board-man-history-compact-en.png 640 560
capture_scene japanese-history 日本語 history board-man-history-ja.png 800 560
capture_scene japanese-templates 日本語 templates board-man-templates-ja.png 800 760
capture_scene japanese-settings 日本語 settings board-man-settings-ja.png 800 820
capture_scene japanese-compact 日本語 history board-man-history-compact-ja.png 640 560

cp "$OUTPUT_DIR/board-man-history-en.png" "$REPO_ROOT/docs/assets/board-man-main-screenshot.png"
cp "$OUTPUT_DIR/board-man-history-en.png" "$REPO_ROOT/assets/readme/board-man-screenshot.png"

for image in "$OUTPUT_DIR"/*.png "$REPO_ROOT/docs/assets/board-man-main-screenshot.png" "$REPO_ROOT/assets/readme/board-man-screenshot.png"; do
  test -s "$image"
  dimensions="$(sips -g pixelWidth -g pixelHeight "$image" 2>/dev/null | awk '/pixelWidth|pixelHeight/{printf "%s ", $2}')"
  echo "Verified $image: $dimensions"
done

echo "Board-Man README screenshots completed with isolated demo profiles."
