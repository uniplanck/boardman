# Board-Man

Board-Man is a macOS clipboard productivity utility derived from Clipy. It keeps recent clipboard history close at hand and adds Board-Man-oriented workflow features for repeated paste work.

Board-Man is a modified derivative work. It is not endorsed by the upstream Clipy or ClipMenu maintainers.

## Features

- History: browse recent clipboard items from the Board-Man panel.
- Pinned: keep important history and snippet items easy to reach.
- Snippets: store reusable text snippets.
- Favorites: review pinned and favorite workflow items in one place.
- Search: filter the active tab with the panel search field.
- Paste: press Enter or click a row to paste into the active app.

## Screenshot

![Board-Man clipboard history](docs/images/boardman-history.png)

### Screenshots to refresh after UI QA

- Refresh `docs/images/boardman-history.png` after a manual UI pass if the panel layout changes again.

## Initial Permission Setup

Board-Man needs macOS privacy permissions for normal paste workflows:

- Accessibility: required for paste/focus automation.
- Input Monitoring: required for global shortcut handling.

Open System Settings > Privacy & Security and enable Board-Man under Accessibility and Input Monitoring when macOS prompts. Do not reset TCC permissions during normal development.

## Preferences

Board-Man preferences include:

- General: launch and history behavior.
- Menu: menu and panel display options.
- Shortcuts: history, snippets, and clear-history hotkeys.
- Types: clipboard content types to save.
- Excluded Apps: apps Board-Man should ignore.
- Updates and Beta: inherited settings panels kept for compatibility.

Some internal source files and classes still use Clipy names to preserve project compatibility.

## Local Build

Requirements:

- macOS
- Xcode with command line tools
- Git

Build smoke:

```bash
xcodebuild -project "Board-Man.xcodeproj" \
  -scheme "Board-Man" \
  -configuration Debug \
  -derivedDataPath /tmp/BoardManPublicBuild \
  -destination 'generic/platform=macOS' \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Optional local install helper:

```bash
./scripts/boardman/install-dev-stable.sh --dry-run
```

The install helper cannot bypass macOS permission prompts. Grant permissions manually in System Settings if prompted.

## Attribution

Board-Man is based on Clipy and preserves upstream license and attribution notices.

See:

- `ATTRIBUTION.md`
- `LICENSE`
- `LICENSE_CLIPMENU`

## Public Repository Policy

Do not commit private logs, local absolute paths, signing material, provisioning profiles, API keys, tokens, production-only scripts, build artifacts, or user-specific configuration.
