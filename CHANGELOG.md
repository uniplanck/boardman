# Changelog

Board-Man follows tagged GitHub releases for published builds. The `main` branch can contain work that has not yet shipped in a downloadable archive.

## Unreleased — v0.2.2 candidate

The current development build is versioned as `0.2.2` / build `4`. It is not a published GitHub Release until a `v0.2.2` tag and release assets are created.

### Clipboard reliability

- Reconciled unintended extra line breaks introduced while clipboard text moves through macOS pasteboard representations.
- Preserved intentional blank lines while removing only line breaks that were artifacts of the clipboard representation path.

### Release metadata

- Advanced app and test bundle metadata from `0.2.1` / build `3` to `0.2.2` / build `4` so local development installs are distinguishable from the published v0.2.1 archive.

## v0.2.1 — 2026-08-19

v0.2.1 is a focused patch release that ships the reliability, typography, shortcut, and repository-cleanup work merged after v0.2.0.

### Reliability and interaction

- Corrected the Japanese empty-state copy for Templates to `定型文はありません`.
- Prevented descender clipping at larger text sizes using font metrics while preserving the visual center of capital letters.
- Made timestamp shortcut hit detection reliable and changed timestamp shortcut actions to paste the selected history item before firing the configured shortcut after its delay.
- Preserved intentionally cleared global shortcuts across rebuilds and relaunches.
- Added bounded Carbon hotkey registration retries so transient registration failures do not leave a shortcut disabled for the rest of the process lifetime.

### Maintenance

- Removed proven-unused source images, legacy status-bar assets, and an unused legacy Template editor XIB.
- Enabled normal Release dead-code stripping while preserving current UI assets and behavior.
- Aligned app/test bundle metadata to `0.2.1` / build `3`.

## v0.2.0 — 2026-08-19

v0.2.0 is the first formal product-line release after the internal 0.0.1 baseline. The project intentionally reset product versioning after the older experimental line. Historical tags already occupy v0.1.0 through v0.1.2 and v1.2.x, so those tags are preserved rather than rewritten; the formal line therefore resumes at v0.2.0.

### Panel and workflow

- Rebuilt the primary panel around History, Templates, and Settings.
- Added quick mode, search improvements, history conditions, usage filters, and keyboard-first navigation.
- Added editable display names, highlights, masking, persistent pins, timed pins, and protected retention behavior.
- Added modern Template creation, editing, grouping, ordering, and shortcut controls.
- Added single-click Template paste with double-click editing.
- Unified pointer hover and `↑` / `↓` row selection behavior.
- Stabilized selection geometry and preserved row, Pin, timestamp, and accessory spacing across panel widths.
- Fixed timestamp shortcut hit handling and refined Appearance card spacing.

### Clipboard and usage tracking

- Improved direct-paste verification and manual paste-count tracking.
- Improved Chromium paste reliability.
- Improved image clipboard identity and image paste counting.
- Added local paste-count visibility and used-item appearance options.
- Added configurable Pin labels and image visibility / preview position controls.
- Improved legacy History and Template recovery, including missing pinned-text payload recovery.

### Settings, licensing, and updates

- Expanded Appearance, timestamp, History, Template, shortcut, privacy, update, and license settings.
- Added local entitlement foundations and Free / Pro presentation without claiming a complete production purchase backend.
- Added Owner Lifetime local-license foundations used by maintainer builds.
- Added the Sparkle update-check foundation while keeping private signing credentials outside the repository.
- Kept production Sparkle appcast publishing disabled until a proper signing/notarization distribution pipeline exists.

### Repository and documentation

- Rebuilt the English and Japanese READMEs around current product behavior and refreshed all translated download references.
- Added deterministic isolated README screenshot generation.
- Added issue forms, pull-request guidance, support, security, conduct, and contribution documentation.
- Expanded CI with repository checks and a macOS build-and-test job.
- Aligned app/test bundle metadata to `0.2.0` / build `2` for this formal release.

## Legacy experimental releases

The historical experimental line remains intact. In particular, existing v0.1.0, v0.1.1, v0.1.2, v1.2.2, and v1.2.3 tags are not reused or rewritten.

- [v1.2.3](https://github.com/uniplanck/boardman/releases/tag/v1.2.3) — legacy experimental release with panel clipping, keyboard selection, preview priority, and opening-flicker fixes.
- [v1.2.2](https://github.com/uniplanck/boardman/releases/tag/v1.2.2) — legacy experimental release with theme, responsive list width, and keyboard navigation improvements.
- [All releases](https://github.com/uniplanck/boardman/releases)
