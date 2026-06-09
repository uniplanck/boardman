# Board-Man 0.0.1 Acceptance Audit

## Purpose

This audit snapshots the current Board-Man 0.0.1 acceptance state against `docs/boardman-0.0.1-acceptance-checklist.md`.

It separates items verified from source, docs, git state, plist metadata, and local build from items that still require local app or GUI verification. It also identifies any code-confirmed release blockers found during this audit.

## Source State Audited

- Branch audited from: `main`
- Commit audited: `d9fb46a7e0dd53d71fbbeb490dfc95cbd13cba01`
- Commit subject: `Document Board-Man 0.0.1 acceptance checklist (#78)`
- Audit timestamp: `2026-06-09 12:24:13 +0900`
- App version/build: `0.0.1 / 1`
- Version evidence: `Clipy/Supporting Files/Info.plist` and `ClipyTests/Info.plist`
- Build evidence: Debug generic macOS build succeeded with `CODE_SIGNING_ALLOWED=NO`
- Working tree note: `_copy/` is intentionally untracked and excluded from this audit and PR.

## Status Legend

- PASS: verified by code, docs, git state, or build
- MANUAL: requires local app/GUI/manual behavior verification
- BLOCKER: must be fixed before 0.0.1 acceptance
- N/A: explicitly out of scope for 0.0.1

## Audit Table

### App Identity / Version

| Checklist item | Status | Evidence | Next action if not PASS |
| --- | --- | --- | --- |
| App identity is Board-Man. | PASS | UI/window strings and docs use Board-Man; recent baseline commits #72-#78 are present on `main`. | N/A |
| App version is 0.0.1. | PASS | PlistBuddy returned `0.0.1` for app and test Info.plist files. | N/A |
| Build number is 1. | PASS | PlistBuddy returned `1` for app and test Info.plist files. | N/A |
| No unrelated version, bundle identity, signing, or release metadata changes are included. | PASS | This PR adds documentation only; `_copy/` remains untracked and excluded. | N/A |

### Clipboard / History Behavior

| Checklist item | Status | Evidence | Next action if not PASS |
| --- | --- | --- | --- |
| App launches successfully. | MANUAL | Local build succeeded, but launch was not performed in this audit. | Launch the app locally and confirm the menu bar app opens. |
| Clipboard monitoring still records expected clipboard history. | MANUAL | `ClipService.startMonitoring()` still observes `NSPasteboard.general.changeCount`; runtime behavior requires a local app session. | Copy new items and confirm they appear in history. |
| Existing paste/history workflows do not regress. | MANUAL | Paste and history source paths remain present; workflow behavior requires local interaction. | Verify menu selection, paste, and history navigation. |
| Free-state limits do not unexpectedly destroy existing local history data. | MANUAL | `ClipService.trimHistoryIfNeeded` enforces the Free history retention limit after save; data-preservation impact must be checked with local history. | Verify existing local history behavior before acceptance. |

### Runtime Entitlement Gates

| Checklist item | Status | Evidence | Next action if not PASS |
| --- | --- | --- | --- |
| Free and Pro states are represented by the entitlement core. | PASS | `Entitlement.swift` defines Free/Pro plans, license states, features, and Free/Pro limits. | N/A |
| Runtime gates prevent Free users from using Pro-only behavior. | PASS | `Entitlement.canUse` requires Pro entitlement and feature membership; Appearance Pro controls call entitlement gates. | N/A |
| Gated behavior fails closed without crashes or ambiguous state. | PASS | Default snapshot is `.freeDefault`; unknown or non-Pro states are not Pro-entitled. | N/A |

### License Free State UI

| Checklist item | Status | Evidence | Next action if not PASS |
| --- | --- | --- | --- |
| License UI clearly represents the current Free state. | MANUAL | `CPYBetaPreferenceViewController` initializes Free Plan, Free status, not verified, and not activated labels. | Open License tab and confirm the Free state is visibly correct. |
| UI does not imply real license activation exists in 0.0.1. | PASS | License field, Activate, Paste, and Deactivate controls are disabled; copy says activation is not connected. | N/A |
| Copy avoids promises of backend validation, device binding, or purchase completion. | PASS | UI copy states activation/device binding are not connected in this build. | N/A |

### Pro Locked Control Pattern

| Checklist item | Status | Evidence | Next action if not PASS |
| --- | --- | --- | --- |
| Pro controls are visible where intended but locked in Free state. | MANUAL | Appearance scaffold creates locked Pro tiles/controls when not Pro-entitled. | Open Appearance and confirm locked controls are visible and disabled. |
| Locked controls cannot be used to bypass entitlement gates. | PASS | `BoardManPreferenceProLockedControlView` disables gated controls unless `EntitlementGate.canUse` passes. | N/A |
| Locked controls provide a clear upgrade path without enabling Pro behavior. | MANUAL | Locked control includes Upgrade action through `BoardManUpgradeRoute`; visual/interaction confirmation remains manual. | Click only the Upgrade path and confirm no Pro control becomes usable. |

### Upgrade CTA Route

| Checklist item | Status | Evidence | Next action if not PASS |
| --- | --- | --- | --- |
| Upgrade CTA opens the intended route or URL without forced unwrap crashes. | MANUAL | `BoardManUpgradeRoute.openProPage()` guards URL construction and opens `https://uniplanck.com/board-man`; actual browser route requires manual verification. | Click Upgrade CTA locally and confirm the intended route opens. |
| Missing or malformed upgrade configuration fails safely. | PASS | `BoardManUpgradeRoute` uses `guard let url` and returns after logging/assertion on invalid URL. | N/A |
| CTA copy does not claim that real purchase or license issuance is implemented. | PASS | CTA copy points to Pro upgrade; License activation copy remains disabled/not connected. | N/A |

### Updates / Sparkle Foundation

| Checklist item | Status | Evidence | Next action if not PASS |
| --- | --- | --- | --- |
| Sparkle/update foundation is present only as intended for 0.0.1. | PASS | `CPYUpdatesPreferenceViewController` uses Sparkle and handles unavailable feed state. | N/A |
| No production appcast is published as part of 0.0.1 acceptance. | PASS | No appcast or release artifact is added by this PR; Updates UI says appcast is not published yet. | N/A |
| No release artifact, private key, signing secret, or update credential is committed. | PASS | Audit found no release artifact/private key addition; existing Sparkle public key material is not a signing secret. | N/A |

### Local Build / Install Verification

| Checklist item | Status | Evidence | Next action if not PASS |
| --- | --- | --- | --- |
| Local app build succeeds from the accepted source state. | PASS | `rtk xcodebuild ... CODE_SIGNING_ALLOWED=NO build` succeeded for Debug generic macOS. | N/A |
| Local install/open path is verified. | MANUAL | Build was performed, but install/open was not performed. | Install/open locally and confirm the menu bar app appears. |
| Basic launch, clipboard, history, license UI, locked control, and upgrade CTA checks pass locally. | MANUAL | These require GUI/runtime interaction. | Complete the manual verification list below. |

### No Unintended Backend / Keychain / Release Scope

| Checklist item | Status | Evidence | Next action if not PASS |
| --- | --- | --- | --- |
| No backend license API is required for 0.0.1 acceptance. | PASS | License activation UI is disabled/not connected; stub response says production activation still requires a backend later. | N/A |
| No Keychain token storage or device binding is required for 0.0.1 acceptance. | PASS | Device binding UI is disabled/not connected; 0.0.1 acceptance does not require real activation. | N/A |
| No payment, customer operation, production release, or appcast publishing work is included. | PASS | This PR is documentation-only and does not create release artifacts, payment/customer changes, or appcast publishing. | N/A |

## Explicitly Out of Scope for 0.0.1

| Item | Status | Evidence | Next action if not PASS |
| --- | --- | --- | --- |
| Real license activation. | N/A | Deferred by checklist and UI copy. | N/A |
| Backend license API. | N/A | Deferred by checklist. | N/A |
| Keychain or device binding. | N/A | Real activation/device binding is deferred by checklist. | N/A |
| Real purchase flow. | N/A | Deferred by checklist. | N/A |
| Production Sparkle appcast or release publishing. | N/A | Deferred by checklist. | N/A |
| Full Appearance redesign. | N/A | Deferred by checklist. | N/A |
| Cloud sync or team features. | N/A | Deferred by checklist. | N/A |
| Export/import implementation unless already present. | N/A | Deferred by checklist. | N/A |
| Payment or customer operations. | N/A | Deferred by checklist. | N/A |

## Release Blocker Assessment

No code-confirmed blocker was found in this audit.

Manual verification remains required before accepting 0.0.1 because launch, clipboard capture, paste/history workflows, License tab rendering, locked Appearance controls, Upgrade CTA routing, and Free-state Pro bypass behavior were not exercised in a running app session.

## Manual Verification Remaining

- Launch the app and confirm the menu bar app opens.
- Confirm clipboard history records new clipboard items.
- Confirm paste/history workflows still work.
- Confirm the License tab shows the Free state correctly.
- Confirm the Appearance Pro locked control is visible and disabled.
- Confirm the Upgrade CTA opens the intended route.
- Confirm no Pro behavior is usable in Free state.

## Next Decision

If the manual checks pass and no blockers remain, Board-Man 0.0.1 can be accepted as the baseline.

If a manual check fails, fix only that blocker before starting new feature work.

## Validation Performed

- `git status --short`
- `git diff --stat`
- `git diff --check`
- `PlistBuddy` version/build check for app and test Info.plist files
- Read `docs/boardman-0.0.1-acceptance-checklist.md`
- Local Debug build with `xcodebuild` through `rtk`
