# README Screenshot Workflow

Board-Man's repository screenshots are generated from isolated temporary profiles. The workflow exists to keep private clipboard history, customer information, tokens, local paths, and other maintainer data out of Git.

## Generated assets

Running the workflow refreshes:

- `docs/assets/screenshots/board-man-history-en.png`
- `docs/assets/screenshots/board-man-templates-en.png`
- `docs/assets/screenshots/board-man-settings-en.png`
- `docs/assets/screenshots/board-man-history-compact-en.png`
- `docs/assets/screenshots/board-man-history-ja.png`
- `docs/assets/screenshots/board-man-templates-ja.png`
- `docs/assets/screenshots/board-man-settings-ja.png`
- `docs/assets/screenshots/board-man-history-compact-ja.png`
- `docs/assets/board-man-main-screenshot.png`
- `assets/readme/board-man-screenshot.png`

The last two files remain as compatibility aliases for older documentation links.

## Safety model

The capture script:

1. Targets only the configured screenshot process name, executable, and bundle identifier.
2. Records whether that target process is already running and stops only that process before capture.
3. Creates a temporary `HOME` and `CFFIXED_USER_HOME` for each scene.
4. Seeds the macOS clipboard with deterministic demo text only.
5. Seeds deterministic demo Template groups only for Debug Template scenes.
6. Launches Board-Man with an explicit screenshot-only environment contract.
7. Exports the panel content view directly to PNG instead of taking a desktop screenshot.
8. Deletes every temporary profile.
9. Replaces the clipboard with a harmless completion message.
10. By default, reopens the canonical app only when it was the configured target and was running before capture.

The app-side export path is compiled only into Debug builds and remains inactive unless `BOARDMAN_SCREENSHOT_OUTPUT` is present. Release builds and normal launches do not open or export the panel automatically.

## Prerequisites

- macOS 13 or later
- Xcode
- a built Board-Man app
- permission to stop and reopen the local Board-Man process

Build a current Debug app:

```bash
xcodebuild \
  -project Board-Man.xcodeproj \
  -scheme Board-Man \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build
```

## Generate screenshots

Point the script at the app produced by the current source tree:

```bash
APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path '*/Build/Products/Debug/Board-Man.app' \
  -type d \
  -print \
  | head -n 1)"

BOARDMAN_SCREENSHOT_APP="$APP_PATH" \
  ./scripts/boardman/capture-readme-screenshots.sh
```

Verify that `APP_PATH` belongs to the current checkout before running the script. Do not silently fall back to an older installed build when documenting a new UI change.

The script accepts an optional output directory:

```bash
BOARDMAN_SCREENSHOT_OUTPUT_DIR=/tmp/boardman-screenshots \
  BOARDMAN_SCREENSHOT_APP=/path/to/Board-Man.app \
  ./scripts/boardman/capture-readme-screenshots.sh
```

For an isolated Candidate build, override the executable, process name, and bundle identifier so the canonical Board-Man process and preferences are untouched:

```bash
BOARDMAN_SCREENSHOT_APP=/path/to/Board-Man\ Candidate.app \
BOARDMAN_SCREENSHOT_EXECUTABLE='Board-Man Candidate' \
BOARDMAN_SCREENSHOT_PROCESS_NAME='Board-Man Candidate' \
BOARDMAN_SCREENSHOT_BUNDLE_ID=com.uniplanck.BoardMan.Candidate \
BOARDMAN_SCREENSHOT_RESTORE_CANONICAL=false \
  ./scripts/boardman/capture-readme-screenshots.sh
```

## Demo clipboard content

English and Japanese scenes use fixed examples covering:

- the default shortcut
- a meeting note
- local-first history and Templates terminology
- a design-review checklist
- the public repository URL
- a harmless Git command
- a reply template
- a release checklist

Template scenes additionally seed fixed `Replies` / `Development` / `Links` groups in English and `返信` / `開発` / `リンク` groups in Japanese. Do not replace these with copied production data, private URLs, real customer messages, tokens, passwords, or local file paths.

## Verification

After generation:

```bash
bash -n scripts/boardman/capture-readme-screenshots.sh
find docs/assets/screenshots -maxdepth 1 -name 'board-man-*.png' -type f -print
```

Then inspect every image and confirm:

- only demo content is visible
- all eight English/Japanese History, Templates, Settings, and compact-width scenes are correct
- no row, Pin badge, timestamp, border, button, tab, or text is clipped
- the compact screenshots preserve horizontal spacing
- language labels match the current product UI
- Template scenes show the deterministic demo groups and a readable selected item
- image dimensions are non-zero and consistent with the requested scene size

A successful script exit proves that files were produced. It does not replace visual review; a technically valid PNG can still contain an obvious layout defect.
