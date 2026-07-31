# README Screenshot Workflow

Board-Man's repository screenshots are generated from isolated temporary profiles. The workflow exists to keep private clipboard history, customer information, tokens, local paths, and other maintainer data out of Git.

## Generated assets

Running the workflow refreshes:

- `docs/assets/screenshots/board-man-history-en.png`
- `docs/assets/screenshots/board-man-history-compact-en.png`
- `docs/assets/screenshots/board-man-settings-en.png`
- `docs/assets/screenshots/board-man-history-ja.png`
- `docs/assets/board-man-main-screenshot.png`
- `assets/readme/board-man-screenshot.png`

The last two files remain as compatibility aliases for older documentation links.

## Safety model

The capture script:

1. Records whether the canonical `/Applications/Board-Man.app` is running.
2. Stops Board-Man before launching the capture build.
3. Creates a temporary `HOME` and `CFFIXED_USER_HOME` for each scene.
4. Seeds the macOS clipboard with deterministic demo text only.
5. Launches Board-Man with an explicit screenshot-only environment contract.
6. Exports the panel content view directly to PNG instead of taking a desktop screenshot.
7. Deletes every temporary profile.
8. Replaces the clipboard with a harmless completion message.
9. Reopens the canonical app when it was running before capture.

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

Do not replace these with copied production data, private URLs, real customer messages, tokens, passwords, or local file paths.

## Verification

After generation:

```bash
bash -n scripts/boardman/capture-readme-screenshots.sh
find docs/assets/screenshots -maxdepth 1 -name 'board-man-*.png' -type f -print
```

Then inspect every image and confirm:

- only demo content is visible
- History, compact width, Settings, and Japanese scenes are correct
- no row, Pin badge, timestamp, border, or text is clipped
- the compact screenshot preserves horizontal spacing
- language labels match the current product UI
- image dimensions are non-zero and consistent with the requested scene size

A successful script exit proves that files were produced. It does not replace visual review; a technically valid PNG can still contain an obvious layout defect.
