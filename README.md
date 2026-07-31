<div align="center">

# Board-Man

**A local-first clipboard workspace for macOS.**

History, reusable templates, pins, search, usage signals, and image previews — one shortcut away.

[![Board-Man CI](https://github.com/uniplanck/boardman/actions/workflows/board-man-ci.yml/badge.svg)](https://github.com/uniplanck/boardman/actions/workflows/board-man-ci.yml)
[![Latest release](https://img.shields.io/github/v/release/uniplanck/boardman?display_name=tag&sort=semver)](https://github.com/uniplanck/boardman/releases/latest)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111111?logo=apple)](https://github.com/uniplanck/boardman/releases/latest)
[![Swift 5](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](https://swift.org)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Download](#download) · [Features](#features) · [Changelog](CHANGELOG.md) · [Build](#build-from-source) · [Contribute](.github/CONTRIBUTING.md) · [日本語](docs/i18n/README.ja.md)

</div>

![Board-Man clipboard history with safe demo content](docs/assets/screenshots/board-man-history-en.png)

Board-Man is a macOS menu bar app derived from [Clipy](https://github.com/Clipy/Clipy). It turns clipboard history into a compact working surface for people who repeatedly move text, URLs, commands, templates, and images between apps.

Clipboard content stays on the Mac. Board-Man does not require a cloud clipboard service.

> **Release status:** the latest downloadable build is **v1.2.3**. The `main` branch is under active development and may contain features that have not yet shipped in a tagged release.

## Why Board-Man

Most clipboard managers answer one question: “What did I copy?” Board-Man also helps answer “What do I reuse?” and “What should become a template?”

- Open history instantly with `⌘⌥V`.
- Pin important entries so they survive cleanup.
- Save reusable text as **Templates**.
- See paste-count signals for frequently used entries.
- Search and navigate without leaving the keyboard.
- Keep text, URLs, commands, and image clipboard entries together.
- Adjust timestamps, panel density, appearance, shortcuts, and retention.
- Mask sensitive rows in the panel without deleting their local data.

## Product tour

<table>
  <tr>
    <td width="50%"><img src="docs/assets/screenshots/board-man-history-en.png" alt="Board-Man clipboard history"></td>
    <td width="50%"><img src="docs/assets/screenshots/board-man-history-compact-en.png" alt="Board-Man compact-width layout"></td>
  </tr>
  <tr>
    <td align="center"><strong>History</strong><br>Search, pins, timestamps, and usage signals.</td>
    <td align="center"><strong>Responsive panel</strong><br>Accessories keep their spacing at narrower widths.</td>
  </tr>
  <tr>
    <td colspan="2"><img src="docs/assets/screenshots/board-man-settings-en.png" alt="Board-Man settings"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><strong>Settings</strong><br>Configure history, templates, shortcuts, timestamps, appearance, privacy, updates, and licensing.</td>
  </tr>
</table>

Japanese interface preview: [docs/assets/screenshots/board-man-history-ja.png](docs/assets/screenshots/board-man-history-ja.png)

## Features

### Clipboard history

- Recent text, links, commands, and image entries from the menu bar.
- Search, keyboard navigation, and direct paste.
- Configurable retention with pinned-item protection.
- Relative timestamps with selectable number, unit, suffix, and “now” styles.
- Per-item display names, highlighting, masking, and timed pins.

### Templates

- Reusable text entries organized into groups.
- Editable display names and content.
- Drag-and-drop ordering.
- Group shortcuts and enable/disable states.

The upstream codebase uses the internal term `snippet`; the product UI uses **Templates** in English and **定型文** in Japanese.

### Usage visibility

- Paste-count badges for frequently used content.
- Optional styling for previously used items.
- Image entries use image-aware identities so generic labels do not collapse into one count.

### Local-first privacy

- History and templates are stored locally.
- No external clipboard synchronization is required.
- Masking hides content in the panel without pretending the underlying data has been deleted.
- Screenshots in this repository are generated from isolated temporary profiles with deterministic demo content — never from a maintainer’s real history.

## Download

The latest published build is [Board-Man v1.2.3](https://github.com/uniplanck/boardman/releases/tag/v1.2.3).

1. Download `Board-Man-v1.2.3.zip`.
2. Unzip it.
3. Move `Board-Man.app` to `/Applications`.
4. Open Board-Man.

If macOS blocks the first launch, Control-click the app and choose **Open**, or allow it from **System Settings → Privacy & Security**.

Board-Man needs Accessibility and Input Monitoring permissions for global shortcuts and reliable pasting. Grant them manually when macOS asks; the project does not bypass TCC protections.

## Basic usage

1. Copy text, a URL, a command, or an image.
2. Press `⌘⌥V` or open Board-Man from the menu bar.
3. Search or move with the arrow keys.
4. Press Return to paste the selected item.
5. Pin durable items or turn repeated text into a Template.

Useful shortcuts inside the panel:

| Action | Shortcut |
|---|---|
| Open Board-Man | `⌘⌥V` |
| History / Templates / Settings | `⌘1` / `⌘2` / `⌘3` |
| Focus search | `⌘F` |
| Move selection | `↑` / `↓` |
| Paste selected item | `Return` |
| Copy selected item | `⌘C` |
| Pin or unpin | `⌘P` |
| Preview | `Space` |

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- Accessibility and Input Monitoring permissions for full paste and shortcut behavior

## Build from source

Requirements: current Xcode, Git, and Swift Package Manager access.

```bash
git clone https://github.com/uniplanck/boardman.git
cd boardman
xcodebuild \
  -project Board-Man.xcodeproj \
  -scheme Board-Man \
  -configuration Debug \
  -destination 'platform=macOS' \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build
```

Run the test suite:

```bash
xcodebuild \
  -project Board-Man.xcodeproj \
  -scheme Board-Man \
  -configuration Debug \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  test
```

Maintainers installing local builds should use [`scripts/boardman/install-dev-stable.sh`](scripts/boardman/install-dev-stable.sh) and read [`docs/boardman-dev-install.md`](docs/boardman-dev-install.md).

## Documentation

- [Changelog](CHANGELOG.md)
- [Japanese README](docs/i18n/README.ja.md)
- [Development install guide](docs/boardman-dev-install.md)
- [QA checklist](docs/BOARDMAN_QA_CHECKLIST.md)
- [Screenshot generation](docs/readme-screenshots.md)
- [Release and update architecture](docs/boardman-release-update-spec.md)
- [Sparkle update foundation](docs/sparkle-updates.md)
- [UI design system](docs/boardman-ui-design-system.md)

Additional community translations are available under [`docs/i18n`](docs/i18n).

## Contributing and support

- [Contributing guide](.github/CONTRIBUTING.md)
- [Security policy](.github/SECURITY.md)
- [Support guide](.github/SUPPORT.md)
- [Community code of conduct](.github/CODE_OF_CONDUCT.md)
- [Open an issue](https://github.com/uniplanck/boardman/issues)

Before opening a pull request, keep changes focused, preserve local-data safety, run the affected tests, and include screenshots for visible UI changes.

## License and attribution

Board-Man is a heavily modified derivative of Clipy and preserves upstream attribution and license notices:

- [`ATTRIBUTION.md`](ATTRIBUTION.md)
- [`LICENSE`](LICENSE)
- [`LICENSE_CLIPMENU`](LICENSE_CLIPMENU)

Board-Man is distributed under the MIT license terms inherited from Clipy. It is not endorsed by the upstream Clipy or ClipMenu maintainers.

The repository's funding links point to the upstream Clipy project; Board-Man does not currently advertise a separate project-specific funding account.
