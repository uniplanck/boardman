# Board-Man Free / Lifetime Commercial Roadmap

Status: authoritative commercial roadmap
Created: 2026-08-27
Product model: **Free + Lifetime only**
Subscription: **NOT OFFERED**

## 1. Approved product contract

Board-Man is sold as a low-cost one-time purchase. There is no subscription tier.

### Free

The Free edition must remain useful as a real clipboard manager while keeping clear reasons to purchase Lifetime.

Initial Free limits:

- history: **100 items**,
- pinned items: **3**,
- Templates/snippets: **5**,
- Template/snippet folders: **1**.

Free always retains:

- normal clipboard capture and paste,
- basic search,
- basic hotkeys,
- privacy and exclusion controls,
- data-integrity and recovery behavior,
- export/import,
- security/reliability fixes and application updates.

The app must never delete existing user data merely because a Free quota is exceeded. Quotas block or cap new/retained usage through explicit policy; they are not a destructive downgrade mechanism.

### Lifetime

Lifetime is a one-time purchase and unlocks the full local paid experience:

- unlimited history,
- unlimited pins,
- unlimited Templates/snippets,
- unlimited Template/snippet folders,
- advanced appearance,
- local analytics,
- advanced search,
- workflow actions,
- Template variables,
- workspace/session features,
- advanced timed-pin behavior,
- future local paid features unless explicitly documented otherwise.

A Lifetime license remains valid across future Board-Man app versions. A version upgrade must not require repurchasing the license.

### Device rule

- one license permits **one active device at a time**,
- the same license code may be reused after the current device is deactivated,
- device deactivation is performed from the user's uniplanck.com MyPage,
- after deactivation, the same code may activate a different Mac,
- a Mac replacement does not require issuing a new lifetime license.

### Purchase and delivery

Planned commerce flow:

1. user purchases Board-Man from the product LP on `uniplanck.com`,
2. the commerce backend creates or assigns a lifetime license,
3. the license code is sent by email,
4. the same license is visible in MyPage,
5. Board-Man activates the code against the commercial service,
6. the service enforces one active device and returns a signed device-bound entitlement token,
7. the app verifies the token locally and stores it securely enough for offline lifetime use.

### Service-backed features

Lifetime guarantees the local paid product and future Board-Man app versions. It does **not** automatically promise perpetual third-party/server operating-cost services such as AI, cloud storage, team infrastructure, or external APIs. Those capabilities require a separate future product decision before shipping.

Legacy subscription/trial token parsing may remain temporarily for backwards compatibility, but no new subscription product, subscription purchase path, or subscription renewal logic should be implemented.

## 2. Commercial architecture principles

- private signing keys never ship in the app repository,
- customer/order/license databases live on the private service side,
- Board-Man receives only signed entitlement material,
- device IDs contain no clipboard contents and must not be derived from private clipboard data,
- activation requests never include clipboard contents,
- local paste/search startup must not depend on service availability after a verified Lifetime activation,
- Free quota checks are centralized in `EntitlementGate` rather than scattered magic numbers,
- Lifetime feature checks are centralized by feature identifiers,
- account/device deactivation is authoritative on the server/MyPage side,
- no subscription polling, grace-period billing logic, or recurring-payment state is part of the new commercial product contract.

# Phase 1 — Commercial Contract and Entitlement Foundation

**Status: PASS / CLOSED — 2026-08-27**

Goal: make the client-side product contract unambiguous before connecting real commerce.

Required work:

- codify Free limits in one central policy,
- codify one-device Lifetime rule,
- codify `supportsSubscription = false`,
- codify lifetime validity across future app versions,
- separate Free local, Lifetime local, and service-backed feature classes,
- make `EntitlementGate` enforce Free limits,
- ensure Lifetime removes those limits,
- ensure Lifetime unlocks local premium feature flags,
- keep export/import available to Free,
- keep existing subscription/trial token parsing only as bounded legacy compatibility,
- update tests to prove boundary behavior,
- remove user-facing wording that implies the new product is a recurring "Pro" subscription where touched by this phase.

### Phase 1 acceptance

- Free limits exactly `100 / 3 / 5 / 1`,
- limit boundary tests PASS,
- Lifetime local feature tests PASS,
- Lifetime limits are unlimited,
- Lifetime service-backed features remain unavailable unless separately entitled by a legacy/service contract,
- subscription-support flag is false,
- one active device policy is represented as `1`,
- future-version lifetime flag is true,
- focused entitlement/license tests PASS,
- affected build/typecheck PASS,
- `git diff --check` PASS,
- no production history trimming or destructive downgrade is connected merely by introducing these central limits; runtime enforcement is added only with an explicit non-destructive migration policy.

Closure evidence:

- `EntitlementGateTests`: `23/23` PASS, `0` failed, `0` skipped,
- Debug build: PASS,
- `git diff --check`: PASS,
- Free limits and Lifetime future-local-feature semantics are centralized and tested,
- production history cleanup remains intentionally disconnected from the new entitlement quota until a non-destructive rollout gate exists.

# Phase 2 — Board-Man Activation and Local Lifetime Token

**Status: ACTIVE**

Goal: turn the existing activation boundary into a real Lifetime activation flow.

Required work:

- enable license-code entry and paste,
- POST only license key + local device ID + bundle ID + client version,
- accept only server-signed lifetime entitlement tokens,
- verify signature, bundle, device binding, token version, and lifetime claims,
- store the verified token locally,
- restore Lifetime entitlement offline at launch,
- provide explicit invalid/revoked/device-mismatch states,
- never expose service secrets in the client,
- update Settings to show masked license and activated device.

# Phase 3 — uniplanck.com Purchase, Issuance, and Email Delivery

Goal: purchase once and automatically receive a usable Lifetime license.

Private service responsibilities:

- product LP checkout completion,
- payment-success authority,
- cryptographically random license-code creation,
- hashed license-key storage where practical,
- purchase/order/customer association,
- one-device activation ledger,
- signed entitlement-token issuance,
- transactional license email,
- idempotent purchase handling,
- admin lookup/reissue/revoke controls,
- no clipboard data storage.

# Phase 4 — MyPage License and Device Management

Goal: the user can manage a one-device lifetime license without contacting support.

MyPage requirements:

- show purchased Board-Man Lifetime license,
- masked-by-default code display with explicit reveal/copy,
- show active Mac/device label and activation time,
- deactivate current device,
- make the activation slot immediately reusable after valid deactivation,
- preserve the same lifetime code when moving to another Mac,
- show audit-safe recent license/device activity,
- rate-limit abusive activation/deactivation cycling without trapping normal hardware replacement.

# Phase 5 — Free/Lifetime UX and Full Product Enforcement

Goal: every visible feature behaves consistently with the approved matrix.

Required work:

- clear Free quota indicators,
- non-destructive upgrade prompt at limits,
- Lifetime badge/state,
- advanced local feature locks wired to central entitlement flags,
- no hidden arbitrary limits outside the central commercial policy,
- existing over-limit data remains readable/exportable,
- downgrade/revocation never destroys user data,
- purchase and MyPage routes point to the canonical uniplanck.com pages.

# Phase 6 — End-to-End Commerce and Release Acceptance

Goal: prove the actual customer journey before public paid distribution.

Acceptance path:

1. test purchase on uniplanck.com,
2. exactly one lifetime license created,
3. email received,
4. license visible in MyPage,
5. first Mac activates successfully,
6. second simultaneous Mac is rejected,
7. MyPage deactivation releases the slot,
8. same license activates on replacement Mac,
9. Lifetime remains active after relaunch/offline use,
10. app update preserves entitlement,
11. Free quotas and Lifetime unlocks behave as documented,
12. refund/revoke/admin recovery paths are verified before production policy enables them.

Release/signing/notarization/Sparkle acceptance remains governed by the Technical Excellence release roadmap.

## 3. Current implementation note

The pre-2026-08-27 client intentionally treated ordinary local features as unrestricted. That earlier entitlement policy is superseded by this approved Free/Lifetime commercial contract. Phase 1 is closed; Phase 2 activation wiring is now the active client work. Legacy token parsing may remain during migration, but new product decisions must use this document as the commercial source of truth.
