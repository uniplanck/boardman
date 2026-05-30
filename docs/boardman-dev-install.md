# Board-Man Dev Install Stability Helpers

## Purpose

These helpers reduce repeated macOS TCC Accessibility and Input Monitoring permission friction during local Board-Man development.

The install script performs a local rebuild/install cycle with:

- Safe app quit
- Automatic backup of current `/Applications/Board-Man.app`
- Clean replacement from Xcode build
- Quarantine attribute removal
- Consistent ad-hoc codesigning
- Codesign verification
- Preservation of `BoardManUsePanelUI` unless overridden
- App reopen

This cannot bypass or automate the initial TCC approval prompts. Grant permissions manually in System Settings > Privacy & Security after first install or if prompted.

## Files

- `scripts/boardman/install-dev-stable.sh`
- `scripts/boardman/status-tcc-friendly.sh`
- `scripts/boardman/local-qa.sh`
- `docs/boardman-dev-install.md`

## Usage

### Status Check

```bash
./scripts/boardman/status-tcc-friendly.sh
```

This prints current state without mutating TCC. Pay attention to duplicate Board-Man app copies because macOS can treat them as separate permission targets.

### Dry Run

```bash
./scripts/boardman/install-dev-stable.sh --dry-run
```

Validates the flow without changing the installed app.

### Stable Install

```bash
./scripts/boardman/install-dev-stable.sh
```

The helper builds the `Board-Man` scheme, backs up the current app, installs to `/Applications/Board-Man.app`, removes quarantine metadata, applies ad-hoc codesigning, verifies codesign, restores the panel UI setting, and reopens the app.

Quick reinstall without rebuild:

```bash
./scripts/boardman/install-dev-stable.sh --no-build
```

Override panel UI:

```bash
./scripts/boardman/install-dev-stable.sh --override-panel-ui=0
```

## Build Smoke

```bash
xcodebuild -project "Board-Man.xcodeproj" -scheme "Board-Man" -configuration Debug -derivedDataPath /tmp/BoardManPublicBuild -destination 'generic/platform=macOS' -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO build
```

## Troubleshooting TCC

- If permissions keep prompting, run the status helper and check for duplicate app copies.
- Keep the installed development app at `/Applications/Board-Man.app`.
- Remove stale permission entries manually in System Settings when needed.
- Do not run destructive TCC reset commands during normal development.

Last updated: 2026-05-30
