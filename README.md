# Board-Man

**English** · [日本語](docs/i18n/README.ja.md) · [简体中文](docs/i18n/README.zh-CN.md) · [한국어](docs/i18n/README.ko.md) · [Español](docs/i18n/README.es.md) · [Français](docs/i18n/README.fr.md) · [Deutsch](docs/i18n/README.de.md) · [Português](docs/i18n/README.pt-BR.md)

Board-Man is a local-first macOS clipboard workspace that brings history, reusable templates, pins, search, usage signals, and image previews into one keyboard-driven panel.

> Board-Man is under active development. The latest downloadable release is **v1.2.3**; `main` may contain features that have not yet shipped in a tagged release.

## Screens and core features

![Board-Man clipboard history with safe demo content](docs/assets/screenshots/board-man-history-en.png)

- Open clipboard history instantly with `⌘⌥V`
- Search and paste text, URLs, commands, and images
- Pin important entries and apply timed pins
- Turn repeated text into reusable Templates
- See paste-count signals for frequently reused content
- Mask sensitive rows without deleting their local data
- Customize timestamps, shortcuts, appearance, retention, and panel behavior
- Keep clipboard data on the Mac without requiring cloud synchronization

### Templates

![Board-Man Templates manager](docs/assets/screenshots/board-man-templates-en.png)

Templates store text you paste repeatedly, such as replies, command patterns, URLs, and release checklists. They can be grouped, reordered, enabled or disabled, edited in place, and opened through group shortcuts.

The upstream code still uses the internal term `snippet`; the product UI uses **Templates** in English and **定型文** in Japanese.

### Settings and languages

![Board-Man Settings](docs/assets/screenshots/board-man-settings-en.png)

Settings cover general behavior, appearance, history, Templates, privacy, updates, licensing, keyboard shortcuts, timestamps, usage indicators, and panel sizing. The interface includes English, Japanese, Simplified Chinese, and Korean product translations, with additional README translations in this repository.

### Compact layout

![Board-Man at its compact width](docs/assets/screenshots/board-man-history-compact-en.png)

At narrower widths, the panel preserves spacing for Pin badges and timestamps while the central preview text absorbs compression. Tab labels also switch to shorter localized forms instead of collapsing into unreadable ellipses.

## Download

Download [Board-Man v1.2.3](https://github.com/uniplanck/boardman/releases/tag/v1.2.3), unzip `Board-Man-v1.2.3.zip`, and move `Board-Man.app` to `/Applications`.

If macOS blocks the first launch, Control-click the app and choose **Open**, or allow it from **System Settings → Privacy & Security**.

Board-Man needs Accessibility and Input Monitoring permissions for global shortcuts and reliable pasting. These permissions must be granted manually; the app does not bypass macOS TCC protections.

## Basic usage

1. Copy text, a URL, a command, or an image.
2. Press `⌘⌥V` or open Board-Man from the menu bar.
3. Search or move through the list with the arrow keys.
4. Press Return to paste the selected item into the original input field.
5. Pin durable entries or save repeated text as a Template.

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
- Accessibility and Input Monitoring permissions for full shortcut and paste behavior

## Build

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

Run the tests with:

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

## Regenerate README images

Build a current Debug app, then run:

```bash
BOARDMAN_SCREENSHOT_APP=/path/to/Board-Man.app \
  ./scripts/boardman/capture-readme-screenshots.sh
```

The script launches isolated temporary Board-Man profiles, replaces the clipboard with deterministic demo content, generates English and Japanese History, Templates, Settings, and compact-width scenes, writes the PNG files under `docs/assets/screenshots/`, removes the temporary profiles, and leaves a harmless completion message on the clipboard. It never uses the maintainer's real clipboard history or Templates database.

See [`docs/readme-screenshots.md`](docs/readme-screenshots.md) for the full workflow and verification checklist.

## Documentation

- [Changelog](CHANGELOG.md)
- [Development install guide](docs/boardman-dev-install.md)
- [QA checklist](docs/BOARDMAN_QA_CHECKLIST.md)
- [Screenshot workflow](docs/readme-screenshots.md)
- [Release and update architecture](docs/boardman-release-update-spec.md)
- [UI design system](docs/boardman-ui-design-system.md)
- [Contributing guide](.github/CONTRIBUTING.md)
- [Security policy](.github/SECURITY.md)
- [Support guide](.github/SUPPORT.md)

## Security

Clipboard history can contain passwords, tokens, customer information, private URLs, and local paths. Review the Privacy settings, mask sensitive rows when useful, and avoid committing real clipboard data, `.env` files, credentials, or local authentication material.

The README screenshots are generated only from isolated demo profiles. Security reports should follow [`.github/SECURITY.md`](.github/SECURITY.md).

## License and attribution

Board-Man is a heavily modified derivative of [Clipy](https://github.com/Clipy/Clipy) and preserves upstream attribution and license notices:

- [`ATTRIBUTION.md`](ATTRIBUTION.md)
- [`LICENSE`](LICENSE)
- [`LICENSE_CLIPMENU`](LICENSE_CLIPMENU)

Board-Man is distributed under the inherited MIT license terms and is not endorsed by the upstream Clipy or ClipMenu maintainers.
