# Board-Man v0.2.2 Candidate Release Notes

Prepared: 2026-08-21
Release status: candidate only; not yet tagged or published on GitHub Releases.

Board-Man v0.2.2 is a focused clipboard-reliability patch over v0.2.1. The candidate keeps the existing History / Templates / Settings workflow and advances the app metadata so local development installs can be distinguished from the published v0.2.1 archive.

## Highlights

- Reconciles unintended extra line breaks introduced while clipboard text moves through macOS pasteboard representations.
- Preserves intentional blank lines instead of flattening meaningful paragraph spacing.
- Keeps the fixes already included in v0.2.1 for shortcut recovery, timestamp paste-then-shortcut actions, large-text descenders, and Template UI behavior.

## Version metadata

- App version: `0.2.2`
- Build: `4`
- Intended Git tag when published: `v0.2.2`
- Architectures for a formal release: Apple Silicon (`arm64`) and Intel (`x86_64`)

## Included work after v0.2.1

The candidate includes the changes merged to `main` after the v0.2.1 tag:

- `6106e23` — reconcile extra clipboard line breaks
- `e5aef84` — preserve intentional clipboard blank lines
- `78c86fd` — merge PR #129

## Distribution status

This file does not publish a release. Until a `v0.2.2` Git tag and release assets are explicitly created, GitHub users should still download the published v0.2.1 archive.

The Sparkle update foundation remains present, but production auto-update distribution still requires a signed release archive, Sparkle EdDSA signature, and `appcast.xml`. Developer ID signing and notarization are also separate release-pipeline work.
