# Board-Man Commercial C3/C4 Implementation Record

Status: **IMPLEMENTATION GREEN / LIVE PRODUCTION HOLD**
Updated: 2026-08-28
Product: **Board-Man Free + one-time Lifetime only**
Subscription: **not offered**

## 1. Authority and repository split

Board-Man native client authority:

`/Users/naomac/MyWorkspace/boardman`

Private Web/service implementation authority:

`/Users/naomac/MyWorkspace2/world`

C3/C4 was implemented in an isolated managed worktree from the canonical Web repository and committed on:

- branch: `feat/boardman-commercial-c3-20260828`
- base: `88140125736d953f697fb4a7c02beca9dd7930c5`
- implementation commit: `2bd823662669c0dbfbf0cd8c5cc357e54fa04101`
- subject: `feat: add Board-Man Lifetime license service`

No production deployment, secret provisioning, customer-data mutation, payment execution, live email, or live license activation was performed as part of the implementation sprint.

## 2. Fixed product contract

- one completed Board-Man Lifetime purchase yields one reusable license code,
- one license has one active server-side device slot,
- the same device may reactivate idempotently,
- a second device is rejected while the slot is occupied,
- the purchaser may release the current device in MyPage,
- after release, the same license code may activate another Mac,
- Lifetime has no product expiry,
- Lifetime remains valid across future Board-Man app versions,
- no subscription, renewal, trial billing, subscription grace period, or recurring payment check is part of the product.

## 3. Enforcement model

The MVP deliberately uses **soft server-slot enforcement**.

The server enforces one active device for new online activations. A previously issued Lifetime token may continue to work on an old Mac that remains permanently offline after MyPage release. This is an explicit offline-first trade-off for a low-cost Lifetime product.

Mandatory periodic online leases, invasive hardware fingerprinting, and punitive always-online DRM are outside the MVP.

## 4. Purchase and issuance flow

Existing payment infrastructure is preserved:

```text
Stripe
  -> existing Cloudflare stripe-webhook Worker
  -> existing GAS purchase webhook
  -> Board-Man-specific verified-purchase gate
  -> HMAC-authenticated private issuer route
  -> Firestore Board-Man license ledger
  -> GAS MailApp delivery
```

Board-Man fulfillment is stricter than the historical generic purchase path:

- Board-Man issuance proceeds only when that Stripe webhook was actually signature-verified,
- the configured Board-Man product/price allowlists must match,
- purchase/session retries return the same derived license instead of minting another license,
- a Board-Man fulfillment failure returns a retry marker to the forwarding Worker,
- the forwarding Worker converts that marker to HTTP `503` so Stripe may retry instead of receiving a false success.

## 5. License-code handling

The private service uses separate secret boundaries for deterministic code derivation and lookup:

- `BOARDMAN_LICENSE_DERIVATION_SECRET`
- `BOARDMAN_LICENSE_LOOKUP_SECRET`

The customer-facing code is deterministically derived from the immutable purchase session plus the private derivation secret. This makes purchase retries idempotent while retaining at least 128 bits of secret-derived code material.

Firestore stores keyed lookup material and a masked suffix, not the plaintext license code. The full code is reconstructed only for authorized delivery or an explicit authenticated MyPage reveal.

## 6. Private issuer authentication

GAS calls the private issuer with a bounded timestamped HMAC request using:

- `BOARDMAN_ISSUER_BASE_URL`
- `BOARDMAN_ISSUER_SHARED_SECRET`
- `X-BoardMan-Issuer-Timestamp`
- `X-BoardMan-Issuer-Signature`

The service:

- accepts only bounded JSON,
- requires a configured shared secret,
- limits timestamp skew,
- verifies the HMAC using Web Crypto,
- exposes only bounded public error codes,
- never places the shared secret in the native client.

Issuer routes:

- `POST /api/internal/boardman/licenses/issue`
- `POST /api/internal/boardman/licenses/mark-delivered`

## 7. Public activation API

Native Board-Man C2 calls:

`POST /v1/licenses/activate`

Request body is exactly:

```json
{
  "license_key": "BOARDMAN-...",
  "device_id": "client-generated stable UUID",
  "bundle_id": "com.uniplanck.BoardMan",
  "client_version": "0.x.y"
}
```

Unknown/privacy-unsafe fields are rejected. Clipboard contents, pasteboard metadata, hostname, username, file paths, app history, and arbitrary analytics are not part of the activation schema.

Successful response:

```json
{
  "status": "activated",
  "message": "Lifetime license activated.",
  "signed_token": "<ES256 compact JWS>"
}
```

Occupied device response is a bounded `409` rejection instructing the user to release the current device in MyPage first.

## 8. Signed Lifetime token

Signing uses P-256 / ES256. The private signing JWK is supplied only through the private service secret boundary:

`BOARDMAN_LICENSE_SIGNING_PRIVATE_JWK`

The native client contains only the verification public key.

Lifetime claims include:

- immutable opaque `license_id`,
- `license_kind = ownerLifetime`,
- `plan = ownerLifetime`,
- `state = ownerLifetime`,
- opaque account subject,
- issued-at time,
- `is_lifetime = true`,
- exact device ID,
- exact Board-Man bundle ID,
- token version `1`,
- no subscription expiry.

The C2 client verifies signature, Lifetime claims, bundle binding, device binding, and token version before saving or applying the token.

## 9. Private data model

C3 uses dedicated Firestore collections:

- `boardmanLicenses`
- `boardmanLicensePurchases`
- `boardmanLicenseEvents`

The ledger records purchase identity, opaque account ownership, status, masked code/device suffixes, server device-slot state, delivery state, and append-only audit events.

Optimistic Firestore update-time preconditions protect activation, release, and delivery updates against lost-update races. Conflicts are retried once and otherwise fail closed.

The service does not persist plaintext signing keys, plaintext signed tokens, clipboard contents, or full device IDs for lookup purposes.

## 10. MyPage contract

Authenticated routes:

- `GET /api/mypage/boardman/license`
- `POST /api/mypage/boardman/license/reveal`
- `POST /api/mypage/boardman/license/release-device`

All three routes use the existing Firebase-user authentication boundary and server-side ownership checks.

The TanStack MyPage implementation:

- lists the signed-in purchaser's Board-Man Lifetime licenses,
- displays a masked code by default,
- reveals the full code only after an explicit user action,
- keeps the revealed code only in in-memory React state,
- shows masked active-device state,
- requires a second confirmation before device release,
- updates the UI after release so the user knows another Mac may activate the same code.

MyPage does not create purchases, grant new entitlements, access signing secrets, or mutate LMS progress.

## 11. Email delivery

The existing GAS `MailApp` infrastructure is reused. After verified Board-Man issuance, GAS sends the Lifetime code to the purchase email and then calls the authenticated delivery-status route.

No new external email vendor or browser-side delivery secret was introduced.

## 12. Implementation evidence

Private Web/service branch evidence:

- C3/C4 functional and wiring suites: **14/14 PASS**,
- related MyPage/commercial regression pack: **31/31 PASS**,
- TanStack `home:typecheck`: **PASS**,
- TanStack `home:build`: **PASS**,
- full `world` test suite: **310/310 PASS**, failed `0`, skipped `0`,
- npm audit after dependency bootstrap: **0 vulnerabilities**,
- `git diff --check`: **PASS**,
- exact implementation commit: `2bd823662669c0dbfbf0cd8c5cc357e54fa04101`,
- isolated implementation worktree clean after commit.

Native C2 evidence:

- focused commercial/licensing tests: **18/18 PASS**,
- full Board-Man regression: **196/196 PASS**, failed `0`, skipped `0`,
- SwiftLint serious violations: **0**,
- affected Debug build: **PASS**.

## 13. Production HOLD gate

Implementation GREEN does not mean production acceptance.

The following remain HOLD until separately authorized and verified:

- production secret provisioning,
- production signing-key custody and key/public-key match verification,
- production Board-Man product/price allowlist values,
- production Pages/Workers/GAS deployment,
- live Stripe payment,
- live Firestore license/customer write,
- live transactional email,
- live first-device activation,
- live MyPage reveal/release,
- live second-device transfer,
- production rollback/recovery acceptance.

No production operation may be inferred from the existence of the implementation commit.

## 14. Next acceptance sequence

1. provision preview/test secrets without exposing values,
2. run local or preview purchase-event fixture through issuer and activation routes,
3. verify the produced JWS against the native Board-Man public key,
4. verify authenticated MyPage list/reveal/release in preview,
5. obtain explicit production-operation authority,
6. deploy the established path,
7. run one bounded live purchase -> email -> MyPage -> first Mac -> release -> second Mac acceptance,
8. only after that mark C3/C4 LIVE PASS / CLOSED.
