# Contributing to Board-Man

Board-Man is a macOS clipboard utility derived from Clipy. Keep public changes focused, buildable, and free of private local paths or secrets.

## Guidelines

- Use Board-Man product wording in public docs and UI-facing copy.
- Preserve legal attribution to Clipy and ClipMenu.
- Keep internal Clipy source names when renaming would risk breakage.
- Do not commit build outputs, local logs, user-specific settings, signing material, tokens, or API keys.
- Do not reset macOS TCC permissions from project scripts.

## Localization

Localization files live under `Clipy/Resources`, `Clipy/Sources/Preferences`, and `Clipy/Sources/Snippets`. English interface changes may require editing the related `.xib` files directly.
