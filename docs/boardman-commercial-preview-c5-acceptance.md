# Board-Man Commercial Preview / C5 Acceptance

Status: **IMPLEMENTATION GREEN / LIVE HOLD**
Updated: 2026-08-28

## Scope

This gate closes the non-production work that can be completed before a live Board-Man sale is authorized:

- verify the already-accepted C2 native activation boundary against the C3/C4 service contract,
- define preview/test signing and product allowlist configuration without storing private keys in Git,
- connect Free/Lifetime limits to actual mutation boundaries,
- preserve existing user data when a restrictive entitlement is applied,
- remove new-product Pro/subscription wording from active UI paths while preserving legacy signed-token parsing compatibility,
- keep basic paste, search, privacy, recovery and export/import available offline.

Production Stripe, customer Firestore mutations, transactional email, production secrets, deployment, release, tag, appcast and `/Applications/Board-Man.app` replacement are outside this gate.

## C5 enforcement model

Commercial restrictions are **admission gates**, not deletion or corruption policies.

| Capability | Free | Lifetime | Enforcement boundary |
|---|---:|---:|---|
| Stored history | 100 | Unlimited | New history record admission before persistence. Existing over-limit history is retained. |
| PIN items | 3 | Unlimited | Permanent PIN insertion. Unpin remains available. Existing over-limit pins remain readable/removable. |
| Templates | 5 | Unlimited | Template creation and import preflight. Existing Templates remain accessible/editable. |
| Template folders | 1 | Unlimited | Folder creation and import preflight. Existing folders remain accessible/editable. |
| Export / import | Available | Available | Export remains unrestricted. Import is available but cannot be used to bypass quantity admission limits. |
| Advanced search | Locked | Available | Saved filters and advanced condition mutation/use. Basic text search remains available. |
| Advanced timed PIN | Locked | Available | Timed-PIN creation/settings. Existing timed PINs may expire or be removed. |
| Advanced appearance | Locked | Available | Custom colors, item highlight, relative-time detail and preview scale. Stored paid preferences are preserved but ignored while Free. |
| Detailed local analytics | Locked | Available | Usage counts/styles and usage filtering. Stored values are preserved but hidden/ignored while Free. |
| Workflow actions | Locked | Available | No executable product surface currently exists beyond the central entitlement policy. |
| Template variables | Locked | Available | No executable product surface currently exists beyond the central entitlement policy. |
| Workspace/session features | Locked | Available | No executable product surface currently exists beyond the central entitlement policy. |

Service-backed capabilities remain a separate entitlement class. Lifetime does not imply unlimited third-party service cost.

## Preview signing contract

The native Release build trusts its embedded ES256/P-256 verification public key and must never contain the matching private key. The C3/C4 service expects `BOARDMAN_LICENSE_SIGNING_PRIVATE_JWK` and signs with the configured `kid` (`boardman-lifetime-v1` by default).

A preview environment therefore needs one of these explicit arrangements before native-to-preview activation can be accepted:

1. configure the preview service with the private key matching the native embedded public key, if that key is available through the authorized secret-management boundary; or
2. add a **Debug-only** verification-public-key override and generate a disposable preview keypair outside Git. Release builds must ignore that override.

No matching private key is present in either repository. That is correct security behavior, so this gate must not fabricate one or weaken Release verification merely to make a demo green.

## Product allowlist contract

The C3/C4 service fails closed unless at least one exact Board-Man identifier is configured:

- `BOARDMAN_PRODUCT_IDS`
- `BOARDMAN_STRIPE_PRICE_IDS`

The GAS fulfillment bridge has the equivalent exact allowlist properties. Production IDs are intentionally not invented in source control. Preview acceptance may use isolated test identifiers only when the corresponding test Stripe/product configuration is explicitly provisioned.

## Verification evidence

Board-Man local enforcement:

- C5 focused admission gate: **28/28 PASS**, failed `0`, skipped `0`.
- Relative-time Free/Lifetime preservation gate: **4/4 PASS**, failed `0`, skipped `0`.
- SwiftLint during the C5 focused build: **270 findings, 0 serious**.
- Both focused test runs: `TEST SUCCEEDED`, exit `0`.
- `git diff --check`: required before the scoped C5 commit.

uniplanck.com private-service / preview readiness:

- C3/C4 service + wiring: **14/14 PASS**.
- preview readiness validator: **3/3 PASS**.
- full uniplanck.com regression: **313/313 PASS**, failed `0`, cancelled `0`, skipped `0`.
- the actual current environment returns **HOLD** when the required secrets and Product/Price allowlists are absent, with `networkRequests = 0` and `writesPerformed = false`.
- preview readiness tooling is committed on the isolated commercial feature branch as `46184e9cdf3e93b4b6221fd39f2cbbf19f3ea9b2` (`test: add Board-Man commercial preview readiness gate`).

This closes the code/test work that can be accepted without live commercial credentials. It does **not** convert the production HOLD below into a PASS.

## Live HOLD

The following remain blocked until explicit production authority and real secrets/configuration exist:

- production signing private key provisioning,
- production Board-Man Stripe Product / Price allowlist,
- production deploy,
- real payment and customer database mutation,
- live transactional email,
- live first-device activation,
- MyPage device release against production data,
- second-device transfer,
- release/sign/notarize/appcast/GitHub Release.
