# Contributing to Board-Man

Thank you for helping improve Board-Man. The project is a macOS clipboard utility with local user data, global shortcuts, Accessibility permissions, and a responsive AppKit panel. Small mistakes can corrupt history or create permission churn, so evidence matters more than optimistic assumptions.

Participation is governed by the repository's [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## Before you start

- Search existing issues and pull requests.
- Keep one pull request focused on one problem.
- Do not include clipboard contents, tokens, passwords, private URLs, customer data, local Realm files, signing keys, or macOS permission databases.
- Preserve upstream attribution and MIT license notices.

## Development setup

Requirements:

- macOS 13 or later
- current Xcode
- Git
- Swift Package Manager network access

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

## Tests

Run focused tests while developing, then the complete suite before requesting review.

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

Tests that share Realm or `UserDefaults` state must remain isolated and deterministic. Do not point tests at a real Board-Man data directory.

## UI changes

For visible changes, verify at minimum:

- normal panel width
- narrow panel width
- History, Templates, and Settings tabs
- keyboard selection and focus
- hover and selected states
- top and bottom of the scroll region
- pinned rows, timestamps, badges, and image previews when relevant

Attach before/after screenshots. Repository screenshots must use the isolated demo workflow described in [`docs/readme-screenshots.md`](../docs/readme-screenshots.md), never a real clipboard history.

## Local installation

Use the stable helper for maintainer builds:

```bash
./scripts/boardman/install-dev-stable.sh
```

It preserves the canonical `/Applications/Board-Man.app` path and stable local signing identity. Do not add Hardened Runtime to a self-signed local build; Sparkle framework validation can reject that combination.

## Documentation and localization

The English [`README.md`](../README.md) is canonical. The maintained Japanese edition is [`docs/i18n/README.ja.md`](../docs/i18n/README.ja.md). Other translations should preserve the source meaning and mark their sync status honestly.

In product-facing text:

- English: **Templates**
- Japanese: **定型文**
- Internal/upstream model names may remain `snippet`

When adding a language, update the relevant `.strings` and `.lproj` resources under `Clipy` and include representative UI verification.

## Pull requests

A useful pull request includes:

- the user-visible problem
- the smallest implemented fix
- affected files
- exact test or build evidence
- screenshots for UI changes
- explicit notes about anything not verified

Do not mix generated files, unrelated formatting, version bumps, or release publication into an otherwise bounded fix.

## Security reports

Do not open public issues for suspected vulnerabilities involving clipboard disclosure, local token handling, update verification, or permission bypass. Follow [`SECURITY.md`](SECURITY.md).
