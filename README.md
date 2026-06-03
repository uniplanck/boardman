# Board-Man

[English](README.md) / [ja](docs/i18n/README.ja.md) / [zh-CN](docs/i18n/README.zh-CN.md) / [es](docs/i18n/README.es.md) / [pt-BR](docs/i18n/README.pt-BR.md) / [ko](docs/i18n/README.ko.md) / [de](docs/i18n/README.de.md) / [fr](docs/i18n/README.fr.md)

Board-Man is a macOS clipboard productivity app derived from Clipy.

It keeps clipboard history available from the menu bar and adds workflow-oriented visibility for people who repeatedly copy, paste, edit, and move text, URLs, commands, and images across apps.

> Status: public candidate. This repository is a sanitized open-source edition prepared from an actively developed private build.

## Screenshot

![Board-Man main screenshot](docs/assets/board-man-main-screenshot.png)

## What Board-Man can do

- Keep recent clipboard history available from the menu bar.
- Save and paste reusable snippets.
- Show paste count badges for frequently used items.
- Handle image clipboard entries, including screenshot-like image-only clipboard content.
- Search clipboard history.
- Navigate the panel from the keyboard.
- Pin important items.
- Adjust shortcuts, history limits, menu behavior, and visual theme options.
- Run locally on macOS without sending clipboard contents to an external service.

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

1. Copy text, a URL, a command, or an image as usual.
2. Open Board-Man from the menu bar.
3. Search or move through the clipboard history.
4. Select an item to paste it into the active app.
5. Use snippets for text you paste repeatedly.

## Clipboard history

Board-Man stores recent clipboard items so you can return to text, URLs, commands, and image clipboard entries without copying them again.

Use this when you want to:

- reuse something copied earlier
- avoid switching between documents only to copy the same text again
- keep recent commands or URLs close at hand
- review the flow of copy/paste-heavy work

## Snippets

Snippets are reusable text entries for phrases, templates, URLs, commands, and other content you paste often.

Typical uses:

- repeated replies
- command templates
- marketing or SNS text blocks
- support messages
- URLs and short boilerplate

## Paste count badges

Paste count badges show how many times an item has been pasted.

This helps you notice:

- text you reuse often
- commands you repeatedly run
- assets or snippets that are central to your workflow
- copy/paste patterns that may be worth turning into snippets or automation

## Image clipboard support

Board-Man supports image clipboard entries and can show image-only clipboard content in the history list.

This is useful when copying:

- screenshots
- graphics
- design references
- visual clipboard content between apps

Image entries use a timestamp-based identity so generic names such as `TIFF image` or `PNG image` do not collide in paste counts.

## Search and keyboard navigation

Use search to filter clipboard history. The panel is designed for keyboard-driven use so you can search, move through results, and paste without leaving the current workflow.

## Settings and appearance

Board-Man includes settings for menu behavior, shortcuts, history limits, and visual appearance. Depending on the current build, you can use theme and lighter display options to make the panel easier to read.

## Privacy

Board-Man is a local macOS utility. Clipboard contents are handled locally by the app. Do not store secrets, tokens, passwords, or private customer data in clipboard history unless you understand the risk.

## License and attribution

Board-Man is a heavily modified derivative work based on Clipy.

This repository preserves upstream attribution and license notices:

- `ATTRIBUTION.md`
- `LICENSE`
- `LICENSE_CLIPMENU`

Board-Man is distributed under the MIT license terms inherited from Clipy. It is not endorsed by the upstream Clipy or ClipMenu maintainers.
