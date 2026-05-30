# Board-Man Dev Install Stability Helpers

## Purpose
These helpers address repeated macOS TCC (Accessibility / Input Monitoring) permission friction during local development of Board-Man v4b. 

The install script performs a safe rebuild/install cycle with:
- Safe app quit
- Automatic backup of current /Applications/Board-Man.app
- Clean replacement from Xcode build
- Quarantine attribute removal (`xattr -rd com.apple.quarantine`)
- Consistent ad-hoc codesigning (`codesign --force --deep --sign -`)
- Codesign verification
- Preservation of `BoardManUsePanelUI` UserDefaults (unless overridden)
- Re-open the app

**Important**: This reduces *stale permission* churn but **cannot bypass or automate** the initial TCC approval prompts. You must still grant permissions manually in System Settings > Privacy & Security after first install or if prompted.

Does not modify any app code, Realm schema, bundle ID, or existing V4B-7 behavior. No prohibited actions (no TCC DB writes, no pushes, etc.).

## Files Added
- `scripts/boardman/install-dev-stable.sh` - Main helper with `--dry-run`, `--no-build`, `--override-panel-ui` options
- `scripts/boardman/status-tcc-friendly.sh` - Read-only diagnostic (bundle info, codesign, UI flag, running status, Spotlight duplicates that can confuse TCC, reminder text)
- `docs/boardman-dev-install.md` - This document

## Usage

### 1. Status Check (recommended first)
```bash
cd /path/to/boardman
./scripts/boardman/status-tcc-friendly.sh
```
This prints current state without side effects. Pay attention to Spotlight duplicates — multiple Board-Man.app copies can cause TCC to treat them differently.

### 2. Dry-Run Test
```bash
./scripts/boardman/install-dev-stable.sh --dry-run
```
Validates logic, shows what it would do, no changes to app or build.

### 3. Perform Stable Install
```bash
./scripts/boardman/install-dev-stable.sh
```
- Builds using `Board-Man.xcodeproj` + `Board-Man` scheme (Release)
- Creates backup in /tmp/
- Installs to fixed path `/Applications/Board-Man.app`
- Runs lightweight (output reduced)
- Preserves your `BoardManUsePanelUI` setting
- Ends with digest copied to clipboard and a local digest file when configured.

For quick re-install without rebuild:
```bash
./scripts/boardman/install-dev-stable.sh --no-build
```

Override panel UI:
```bash
./scripts/boardman/install-dev-stable.sh --override-panel-ui=0
```

## Build/Test Notes
- Tested in dry-run mode + status helper.
- Uses existing project conventions from disabled GitHub workflows (xcodebuild flags for Board-Man scheme).
- Commit message used: `chore: add stable Board-Man dev install helpers`
- Current head remains `ea6ae8b` (fix: use single-click paste in Board-Man panel)
- No app functionality changed.
- After install, re-grant TCC if macOS prompts (helper makes subsequent runs more stable).

## Troubleshooting TCC
- If permissions keep resetting: Use status script, manually remove old entries in System Settings, reinstall with this helper.
- Multiple Spotlight-indexed copies (seen in backups) are a common source of issues — consider cleaning old backups.
- The helper explicitly avoids any TCC mutation commands.

Run `scripts/boardman/status-tcc-friendly.sh` after install for confirmation.

Last updated: $(date)
