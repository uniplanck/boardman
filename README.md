# Board-Man

[English](README.md) / [ja](docs/i18n/README.ja.md) / [zh-CN](docs/i18n/README.zh-CN.md) / [es](docs/i18n/README.es.md) / [pt-BR](docs/i18n/README.pt-BR.md) / [ko](docs/i18n/README.ko.md) / [de](docs/i18n/README.de.md) / [fr](docs/i18n/README.fr.md)

Board-Man is a macOS clipboard productivity app derived from Clipy.

It keeps clipboard history available from the menu bar and adds workflow-oriented visibility for people who repeatedly copy, paste, edit, and move text or images across apps.

> Status: public candidate. This repository is a sanitized open-source edition prepared from an actively developed private build.

## Screenshot

![Board-Man main screenshot](docs/assets/board-man-main-screenshot.png)

## What Board-Man can do

- Keep recent clipboard history available from the menu bar.
- Save and paste reusable snippets.
- Show paste count badges so frequently pasted items are easier to notice.
- Handle image clipboard entries, including image-only clipboard content.
- Search clipboard history and navigate the panel from the keyboard.
- Provide settings for shortcuts, menu behavior, history limits, and Board-Man theme/lighter mode.
- Run locally on macOS without sending clipboard contents to an external service.

## Download

- [Download Board-Man v1.2.3](https://github.com/uniplanck/boardman/releases/tag/v1.2.3)
- macOS app archive: `Board-Man-v1.2.3.zip`

## Install and first launch

1. Download `Board-Man-v1.2.3.zip` from the release page.
2. Unzip the archive.
3. Move `Board-Man.app` to `/Applications`.
4. Open Board-Man.

If macOS Gatekeeper blocks the first launch, open **System Settings > Privacy & Security** and allow Board-Man, or Control-click the app and choose **Open**. This is expected for some early public builds.

## Basic usage

- Use the menu bar icon to open clipboard history.
- Select a history item to paste it into the active app.
- Use search to narrow the list when history grows.
- Use keyboard navigation in the panel to move through items quickly.
- Open preferences to adjust shortcuts, history size, menu behavior, and theme options.

## Clipboard history

Board-Man stores recent clipboard items so you can return to text, URLs, and image clipboard entries without copying them again. History settings let you control how much is kept and how menu behavior works.

## Snippets

Snippets are reusable text entries for phrases, templates, URLs, and other content you paste often. Use the snippet editor to create folders and snippets, then paste them from the menu or snippet shortcut.

## Paste count badges

Board-Man can show paste count badges for clipboard items. These badges make repeated paste activity visible, which helps when reviewing repetitive writing, editing, development, or operations work.

## Image clipboard support

Board-Man supports image clipboard entries and can display image-only content in the clipboard list. This is useful when copying screenshots, graphics, or other visual clipboard content between apps.

## Search and keyboard navigation

Use search to filter clipboard history. The panel is designed for keyboard-driven use so you can search, move through results, and paste without leaving the current workflow.

## License and attribution

Board-Man is a heavily modified derivative work based on Clipy.

This repository preserves upstream attribution and license notices:

- `ATTRIBUTION.md`
- `LICENSE`
- `LICENSE_CLIPMENU`

Board-Man is distributed under the MIT license terms inherited from Clipy. It is not endorsed by the upstream Clipy or ClipMenu maintainers.
