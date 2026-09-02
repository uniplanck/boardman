# Board-Man Paste Reliability Matrix

Status: P5.1 automated PASS / real-application manual acceptance OPEN
Updated: 2026-08-27

This document separates deterministic automated coverage from real-application acceptance. A target is not marked manually accepted merely because its bundle family has an automated policy test.

Current automated checkpoint: Phase 5 focused suite `40/40` PASS and full regression `183/183` PASS, with `0` failed and `0` skipped tests. Every manual row remains `pending` until the corresponding real application and interaction case is exercised.

## Target families

| Target | Family policy | Automated coverage | Manual acceptance |
|---|---|---|---|
| Safari | safari | target-family settle profile, paste-count target-change contract, text reconciliation | pending |
| Chrome / Chromium | chromium | extended activation settle, target-change contract, Chromium HTML newline reconciliation | pending |
| Firefox | firefox | Firefox-specific activation settle profile, generic target-change contract | pending |
| Native AppKit text fields | nativeOrUnknown | default settle profile, editable-target change confirmation | pending |
| Electron apps | electron | extended activation settle for Slack/Discord/VS Code/Obsidian/Notion/Postman families | pending |
| Terminal / iTerm2 / Warp / Ghostty | terminal | terminal-family settle profile, shell-history eligibility rules | pending |
| IDE/editor native targets | nativeOrUnknown | default settle profile, shortcut dispatch contract | pending |
| Rich-text destinations | target-family dependent | rich/plain clipboard reconciliation guards | pending |
| Image/file paste paths | target-family dependent | archived payload round-trip and image fingerprint coverage | pending |

## Interaction cases

| Case | Automated evidence | Manual evidence |
|---|---|---|
| normal paste | `PasteCountInputServiceTests`, panel paste coordinator regression | pending per target |
| paste + shortcut | shortcut dispatch and timestamp/paste sequencing regression | pending per target |
| delayed/time action | bounded timestamp shortcut delay and paste-first sequencing | pending per target |
| target-switch race | editable-target observation and activation retry/settle policy | pending per target |
| Accessibility permission loss/regrant | event-tap fallback contract | pending system-level acceptance |
| rapid repeated invocation | hotkey debounce + paste-count dedupe contracts | pending stress acceptance |

## Acceptance rule

A row can move from `pending` only after the real target application is exercised with the applicable interaction cases on the release candidate being accepted. Automated tests remain mandatory even after manual acceptance. Failures must be classified as Board-Man dispatch, target activation/focus, clipboard representation, Accessibility permission, or target-application behavior before changing timing constants.

The current family policy intentionally gives Chromium and common Electron targets a longer activation settle window, Firefox an intermediate window, and Safari/native/terminal targets the normal window. These values are bounded policy, not permission to add arbitrary sleeps elsewhere.
