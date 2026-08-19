# Board-Man v0.2.1 Release Notes

Release date: 2026-08-19

Board-Man v0.2.1 is a focused patch release for the formal product line introduced by v0.2.0. It keeps the same core History / Templates / Settings workflow while shipping reliability, typography, shortcut, and maintenance fixes merged after v0.2.0.

## Highlights

- Corrected the Japanese empty-state copy for Templates to `定型文はありません`.
- Prevented descender clipping at larger text sizes using font metrics while preserving the visual center of capital letters.
- Made timestamp shortcut hit detection reliable.
- Changed timestamp shortcut actions to paste the selected history item first, then fire the configured shortcut after the configured delay.
- Preserved intentionally cleared global shortcuts across rebuilds and relaunches.
- Added bounded Carbon hotkey registration retries so transient registration failures do not leave a shortcut disabled for the remainder of the process lifetime.
- Removed proven-unused source images, legacy status-bar assets, and an unused legacy Template editor XIB.
- Enabled normal Release dead-code stripping without changing the shipped UI asset catalog or intended product behavior.

## Download

Use the versioned archive attached to the GitHub Release:

- `Board-Man-v0.2.1.zip`

`Board-Man-latest.zip` contains the same build for convenience.

After extracting, move `Board-Man.app` to `/Applications`.

## macOS security note

This release follows the current public distribution model and is not notarized with an Apple Developer ID distribution identity. macOS may therefore block the first launch. If that happens, Control-click `Board-Man.app` and choose **Open**, or allow it from **System Settings → Privacy & Security**.

Board-Man requires Accessibility and Input Monitoring permissions for global shortcuts and direct-paste behavior.

## Updates / Sparkle

The app contains the Sparkle update foundation, but v0.2.1 does **not** publish a production `appcast.xml`. A proper Sparkle release requires a separate private EdDSA signing key and production distribution/notarization pipeline. The in-app update check therefore continues to fail safely with the existing feed-not-published message.

## Version metadata

- App version: `0.2.1`
- Build: `3`
- Git tag: `v0.2.1`
- Architectures: Apple Silicon (`arm64`) and Intel (`x86_64`)

## Included work

v0.2.1 includes the changes merged through PR #127 after the v0.2.0 tag, including PR #125, PR #126, and PR #127.

## Legacy releases

Existing v0.2.0 and the older experimental v0.1.x / v1.2.x releases remain available for historical reference. Their tags are intentionally left immutable.
