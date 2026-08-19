# Board-Man v0.1.0 Release Notes

Release date: 2026-08-19

Board-Man v0.1.0 is the first formal product-line release after the internal 0.0.1 baseline. The repository intentionally reset versioning from the older v1.2.3 experimental line, so v0.1.0 is newer even though its semantic version is numerically lower.

## Highlights

- Rebuilt the main workflow around History, Templates, and Settings.
- Added keyboard-first navigation with pointer/keyboard selection kept in sync.
- Added single-click Template paste and double-click Template editing.
- Added persistent and timed Pins, configurable Pin labels, masking, usage styling, and image controls.
- Expanded Appearance with card-based controls and live preview.
- Improved direct paste reliability, including Chromium-based browsers.
- Improved clipboard/image identity, paste counting, and legacy payload recovery.
- Expanded timestamp presentation and actions, including corrected timestamp shortcut hit handling.
- Added local entitlement and Owner Lifetime foundations while keeping online purchase activation explicitly unavailable.
- Refreshed README documentation and deterministic English/Japanese screenshots.

## Download

Use the versioned archive attached to the GitHub Release:

- `Board-Man-v0.1.0.zip`

`Board-Man-latest.zip` contains the same build for convenience.

After extracting, move `Board-Man.app` to `/Applications`.

## macOS security note

This release is not notarized with an Apple Developer ID distribution identity. macOS may therefore block the first launch. If that happens, Control-click `Board-Man.app` and choose **Open**, or allow it from **System Settings → Privacy & Security**.

Board-Man still requires Accessibility and Input Monitoring permissions for global shortcuts and direct-paste behavior.

## Updates / Sparkle

The app contains the Sparkle update foundation, but v0.1.0 does **not** publish a production `appcast.xml`. A proper Sparkle release requires a separate private EdDSA signing key and production distribution/notarization pipeline. The in-app update check therefore continues to fail safely with the existing feed-not-published message.

## Version metadata

- App version: `0.1.0`
- Build: `2`
- Git tag: `v0.1.0`

## Legacy releases

v1.2.3 and earlier releases remain available for historical reference as the old experimental line. They are not newer than v0.1.0 in the current product-line chronology.
