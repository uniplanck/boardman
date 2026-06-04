# Freemium Implementation Plan

## Phase 0: Finish/Merge Manual Cmd+V Paste Count PR If Still Open

- Goal: avoid mixing freemium work with paste count behavior changes.
- Likely files: existing paste count PR files only.
- Validation: existing paste count validation from that PR.
- Risk: behavior regressions if freemium gates are layered on unstable paste logic.
- Done condition: paste count PR is merged or explicitly deferred.

## Phase 1: Documentation And Design Assets

- Goal: add specs and reference images only.
- Likely files: `docs/`, `docs/assets/boardman-freemium-design/`.
- Validation: `git diff --check`.
- Risk: docs drift from future implementation.
- Done condition: docs and images are merged with no production behavior changes.

## Phase 2: Local Entitlement Core

- Goal: add local Free entitlement model and centralized gate.
- Likely files: app model/service area for licensing, Preferences support types, tests if present.
- Validation: unit tests or small local entitlement checks.
- Risk: scattered checks if the gate is not centralized.
- Done condition: app can answer entitlement queries with Free defaults only.

## Phase 3: Free/Pro Gates In UI And Execution Layer

- Goal: apply entitlement checks to selected Pro features.
- Likely files: Preferences views, clipboard/snippet execution paths, menu item handlers.
- Validation: Free state cannot execute Pro-only behavior even if UI is bypassed.
- Risk: UI-only gating or accidental regression of Free features.
- Done condition: selected gates are enforced in UI and behavior paths.

## Phase 4: License Preferences UI Mock

- Goal: add non-network License tab UI states.
- Likely files: Preferences window/tab controllers or SwiftUI views.
- Validation: Free, Trial, Pro, Expired, Invalid, and Offline Grace states render.
- Risk: mock UI implying server behavior that does not exist yet.
- Done condition: License tab is visual only and does not call production APIs.

## Phase 5: Keychain Device ID And Signed-Token Model

- Goal: generate persistent device id and define token verification surface.
- Likely files: Keychain helper, license model, entitlement service.
- Validation: device id persists across app relaunch and token stub verifies expected cases.
- Risk: storing identifiers in weak storage or changing user data unexpectedly.
- Done condition: Keychain device id exists and signed-token verification is stubbed locally.

## Phase 6: uniplanck.com License API Integration

- Goal: connect activation and verification to the production license API when ready.
- Likely files: license API client, activation view model, networking layer.
- Validation: mocked API tests first, then staging API validation.
- Risk: premature production calls, token exposure, or weak error handling.
- Done condition: app can activate against the approved API without exposing secrets.

## Phase 7: Activation/Deactivation/Reset

- Goal: support full license lifecycle.
- Likely files: license service, Preferences License tab, API client.
- Validation: activate, deactivate, reset-required, revoked, and expired flows.
- Risk: locking legitimate users out or leaving stale device bindings.
- Done condition: lifecycle states are recoverable and auditable.

## Phase 8: Hardening/Audit

- Goal: add anti-tamper layers and operational visibility.
- Likely files: entitlement gate, token verification, audit logging, debug build flags.
- Validation: release build has no debug override and logs key state transitions.
- Risk: over-hardening that breaks legitimate offline usage.
- Done condition: layered checks exist without fragile user-facing failures.

## Phase 9: LP/Download/Product Flow Integration On uniplanck.com

- Goal: align website purchase, download, and support flows with app licensing.
- Likely files: uniplanck.com product page, download page, purchase flow, support docs.
- Validation: Free download path, Pro purchase path, license email, reset path.
- Risk: website copy diverges from app entitlement behavior.
- Done condition: website and app describe the same Free/Pro model.
