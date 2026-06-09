# Board-Man 0.0.1 Acceptance Checklist

## Purpose

This checklist defines the completion boundary for Board-Man 0.0.1. Its purpose is to make acceptance explicit and prevent endless scope expansion before the first accepted baseline.

## Current Baseline

- Version: 0.0.1 / build 1.
- #72 established the Board-Man 0.0.1 baseline.
- #73 added the Entitlement Core MVP.
- #74 added runtime entitlement gates.
- #75 added License Free State UI.
- #76 added the Pro locked control entry pattern.
- #77 hardened the Upgrade CTA.

## Acceptance Checklist

### App Identity / Version

- [ ] App identity is Board-Man.
- [ ] App version is 0.0.1.
- [ ] Build number is 1.
- [ ] No unrelated version, bundle identity, signing, or release metadata changes are included.

### Clipboard / History Behavior

- [ ] App launches successfully.
- [ ] Clipboard monitoring still records expected clipboard history.
- [ ] Existing paste/history workflows do not regress.
- [ ] Free-state limits do not unexpectedly destroy existing local history data.

### Runtime Entitlement Gates

- [ ] Free and Pro states are represented by the entitlement core.
- [ ] Runtime gates prevent Free users from using Pro-only behavior.
- [ ] Gated behavior fails closed without crashes or ambiguous state.

### License Free State UI

- [ ] License UI clearly represents the current Free state.
- [ ] UI does not imply real license activation exists in 0.0.1.
- [ ] Copy avoids promises of backend validation, device binding, or purchase completion.

### Pro Locked Control Pattern

- [ ] Pro controls are visible where intended but locked in Free state.
- [ ] Locked controls cannot be used to bypass entitlement gates.
- [ ] Locked controls provide a clear upgrade path without enabling Pro behavior.

### Upgrade CTA Route

- [ ] Upgrade CTA opens the intended route or URL without forced unwrap crashes.
- [ ] Missing or malformed upgrade configuration fails safely.
- [ ] CTA copy does not claim that real purchase or license issuance is implemented.

### Updates / Sparkle Foundation

- [ ] Sparkle/update foundation is present only as intended for 0.0.1.
- [ ] No production appcast is published as part of 0.0.1 acceptance.
- [ ] No release artifact, private key, signing secret, or update credential is committed.

### Local Build / Install Verification

- [ ] Local app build succeeds from the accepted source state.
- [ ] Local install/open path is verified.
- [ ] Basic launch, clipboard, history, license UI, locked control, and upgrade CTA checks pass locally.

### No Unintended Backend / Keychain / Release Scope

- [ ] No backend license API is required for 0.0.1 acceptance.
- [ ] No Keychain token storage or device binding is required for 0.0.1 acceptance.
- [ ] No payment, customer operation, production release, or appcast publishing work is included.

## Explicitly Out of Scope for 0.0.1

- Real license activation.
- Backend license API.
- Keychain or device binding.
- Real purchase flow.
- Production Sparkle appcast or release publishing.
- Full Appearance redesign.
- Cloud sync or team features.
- Export/import implementation unless already present.
- Payment or customer operations.

## Release Blockers

- App does not launch.
- Paste or history behavior regresses.
- Free limits unexpectedly destroy existing data.
- License UI misrepresents real activation as available.
- Pro controls are usable in Free state.
- Upgrade CTA can crash due to forced unwrap or crash-prone URL handling.
- Version/build mismatch from 0.0.1 / build 1.
- Release artifact, private key, signing secret, or production appcast is accidentally published or committed.

## 0.0.2+ Backlog

- Real activation API.
- Keychain token storage.
- Device binding.
- Production landing page, payment, and license issuance.
- Signed release and appcast pipeline.
- Appearance polish and full advanced controls.
- Export/import.
- Analytics improvements.
- Sync, team, and cloud features.

## Decision Rule

Board-Man 0.0.1 is accepted when all acceptance checklist items are checked and no release blockers remain. Do not add new feature work before resolving blockers unless explicitly approved.
