# Board-Man Permission Diagnostics

Use this when Board-Man can open but paste shortcuts, focus restore, or global
input handling are inconsistent.

## Rules

- Do not reset TCC.
- Do not edit the TCC database.
- Do not change the bundle identifier.
- Do not log clipboard contents.
- Do not keep multiple active Board-Man copies installed.

## Quick Checks

From the repo root:

```bash
./scripts/boardman/status-tcc-friendly.sh
```

Confirm:

- `/Applications/Board-Man.app` exists.
- Bundle ID is `com.uniplanck.BoardMan`.
- Codesign verification is OK.
- There are no unexpected Spotlight duplicates.
- The running process state matches what you expect.

## Accessibility

Open System Settings > Privacy & Security > Accessibility.

Confirm `Board-Man` is present and enabled. If there are duplicate entries,
disable the stale entry and keep only the `/Applications/Board-Man.app` copy.

## Input Monitoring

Open System Settings > Privacy & Security > Input Monitoring.

Confirm `Board-Man` is present and enabled. If the app was rebuilt or replaced,
quit and reopen Board-Man after manually confirming the setting.

## If Permission Prompts Reappear

Use the stable install helper so the app path and signing identity stay
consistent:

```bash
./scripts/boardman/install-dev-stable.sh
```

Then inspect status again:

```bash
./scripts/boardman/status-tcc-friendly.sh
```

If duplicates remain, remove stale app copies outside `/Applications` and retry
the read-only status check. Do not use destructive TCC reset commands.

## What This Cannot Prove

macOS does not expose a complete read-only CLI status API for another app's
Accessibility and Input Monitoring grants. Treat System Settings as canonical.
