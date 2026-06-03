# Board-Man

[English](README.md) / [ja](docs/i18n/README.ja.md) / [zh-CN](docs/i18n/README.zh-CN.md) / [es](docs/i18n/README.es.md) / [pt-BR](docs/i18n/README.pt-BR.md) / [ko](docs/i18n/README.ko.md) / [de](docs/i18n/README.de.md) / [fr](docs/i18n/README.fr.md)





Board-Man is a macOS clipboard productivity utility derived from Clipy.

It extends the clipboard manager concept with workflow-oriented features such as paste activity visibility, menu bar feedback, and operator-friendly usage for people who repeatedly write, paste, edit, and move text across apps.

> Status: public candidate. This repository is a sanitized open-source edition prepared from an actively developed private build.

## Screenshot

![Board-Man main screenshot](docs/assets/board-man-main-screenshot.png)

## What Board-Man can do

Board-Man is a macOS clipboard productivity app derived from Clipy. It keeps clipboard history available from the menu bar and adds workflow-oriented visibility for people who repeatedly copy, paste, edit, and move text or images across apps.

Main features:

- Clipboard history from the menu bar
- Reusable snippets for phrases, templates, URLs, and repeated text
- Paste count badges for frequently used items
- Image clipboard support, including screenshot-like image-only entries
- Search and keyboard navigation
- Pinning and menu-friendly workflow controls
- Settings for shortcuts, history limits, menu behavior, and visual theme options
- Local macOS operation without sending clipboard contents to an external service

## Download

- [Download Board-Man v1.2.3](https://github.com/uniplanck/boardman/releases/tag/v1.2.3)
- macOS app archive: `Board-Man-v1.2.3.zip`

## Install and first launch

1. Download `Board-Man-v1.2.3.zip` from the release page.
2. Unzip the archive.
3. Move `Board-Man.app` to `/Applications`.
4. Open Board-Man.

If macOS Gatekeeper blocks the first launch, open **System Settings > Privacy & Security** and allow Board-Man, or Control-click the app and choose **Open**.

## Basic usage

1. Copy text, a URL, or an image as usual.
2. Open Board-Man from the menu bar.
3. Search or move through the clipboard history.
4. Select an item to paste it into the active app.
5. Use snippets for text you paste repeatedly.

## Clipboard history

Board-Man stores recent clipboard items so you can return to text, URLs, and image clipboard entries without copying them again. History settings let you control how much is kept and how the menu behaves.

## Snippets

Snippets are reusable text entries for phrases, templates, URLs, and other content you paste often. They are useful for repeated replies, commands, boilerplate text, and short templates.

## Paste count badges

Paste count badges show how many times an item has been pasted. This makes repeated paste activity visible and helps identify the text, commands, or assets you use most often.

## Image clipboard support

Board-Man supports image clipboard entries and can show image-only clipboard content in the history list. This is useful when copying screenshots, graphics, or other visual clipboard content between apps.

## Search and keyboard navigation

Use search to filter clipboard history. The panel is designed for keyboard-driven use so you can search, move through results, and paste without leaving the current workflow.


## License

Board-Man is distributed under the MIT license terms inherited from Clipy.

The original license and attribution notices are preserved in:

- `LICENSE`
- `LICENSE_CLIPMENU`
- `ATTRIBUTION.md`

Board-Man is a modified derivative work and is not endorsed by the upstream Clipy or ClipMenu maintainers.
