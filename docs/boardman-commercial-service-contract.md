# Board-Man Lifetime Commercial Service Contract

Status: public client boundary implemented; private commerce service pending
Updated: 2026-08-27
Product model: Free + one-time Lifetime only
Subscription: not offered

## 1. Purpose and repository boundary

The public Board-Man macOS client owns local entitlement verification and user-facing activation behavior. The private uniplanck.com service owns purchases, customer/order records, license issuance, device activation state, email delivery, MyPage management, revocation policy, and the ES256 signing private key.

The public repository may contain:

- activation request/response models,
- a public verification key,
- signed-token parsing and verification,
- local device identity,
- local verified-token storage,
- Free/Lifetime entitlement gates,
- public protocol documentation.

It must never contain:

- the signing private key,
- payment-provider secrets,
- customer or order records,
- production database credentials,
- administrative credentials,
- private anti-abuse rules,
- clipboard contents sent for licensing.

## 2. Approved commercial contract

New sales use one product only: **Board-Man Lifetime**.

- one purchase creates or assigns one license code,
- one license permits one active device at a time,
- the same code is reused after MyPage deactivation,
- Lifetime has no product expiry,
- Lifetime remains valid across future Board-Man app versions,
- no recurring billing, renewal, paid trial, subscription grace period, or subscription polling is implemented.

Legacy subscription/trial token shapes may remain parseable for compatibility. They are not accepted as the response to a new Lifetime activation request.

## 3. Purchase and delivery flow

1. The customer purchases Board-Man Lifetime from the product LP on `uniplanck.com`.
2. Payment-success handling creates or assigns exactly one Lifetime license id/code idempotently.
3. The code is delivered by transactional email.
4. The same code is visible in the customer's MyPage.
5. The customer enters the code in Board-Man.
6. Board-Man activates the code for its local device id.
7. The service enforces the one-active-device ledger.
8. The service returns a signed, device-bound Lifetime entitlement token.
9. Board-Man verifies and stores only the verified token.
10. Board-Man restores Lifetime locally on later launches, including when the service is temporarily unreachable.

## 4. Activation endpoint

The public client expects:

`POST /v1/licenses/activate`

The base URL is supplied by build/runtime configuration:

- environment variable: `BOARD_MAN_COMMERCIAL_SERVICE_BASE_URL`
- Info.plist key: `BoardManCommercialServiceBaseURL`

The public client must not contain a private service secret.

### Request

```json
{
  "license_key": "USER-SUPPLIED-LICENSE-CODE",
  "device_id": "LOCAL-STABLE-RANDOM-UUID",
  "bundle_id": "com.uniplanck.BoardMan",
  "client_version": "0.x.y"
}
```

Only these fields are permitted in the activation payload. Clipboard contents, history titles, Templates, payload bytes, file paths, and paste analytics are forbidden.

### Successful response

```json
{
  "status": "activated",
  "message": "Lifetime license activated.",
  "signed_token": "<compact ES256 token>"
}
```

### Rejection examples

The service may reject with non-2xx status and a safe message for conditions such as:

- unknown or malformed code,
- revoked/refunded license,
- another active device already occupies the slot,
- unsupported product,
- abuse/rate-limit policy,
- invalid bundle or client request.

The client treats all non-2xx responses as rejected and must not persist any token from them.

## 5. Lifetime token claim shape

New activation accepts only this claim family:

```json
{
  "license_id": "LICENSE-ID-OR-MASK-SAFE-ID",
  "license_kind": "ownerLifetime",
  "plan": "ownerLifetime",
  "state": "ownerLifetime",
  "features": [],
  "issued_to": "optional-safe-customer-label",
  "sub": "optional-customer-subject",
  "iat": 1780000000,
  "is_lifetime": true,
  "device_id": "LOCAL-STABLE-RANDOM-UUID",
  "bundle_id": "com.uniplanck.BoardMan",
  "token_version": 1
}
```

Requirements:

- compact token format is valid,
- `alg = ES256`,
- signature is valid against the embedded public key,
- `token_version = 1`,
- license kind, plan, and state are all Lifetime-compatible,
- `is_lifetime = true`,
- `exp` is absent,
- `device_id` matches the requesting Mac,
- `bundle_id` matches Board-Man.

Lifetime-local feature availability is defined by the client contract, not frozen forever to the token's original feature array. This preserves the promise that future local Lifetime features do not require reissuing every old license token.

Service-backed feature claims remain explicit. Lifetime ownership alone does not imply perpetual cloud, AI, team, storage, or API service access.

## 6. Legacy compatibility boundary

The verifier/parser may continue to understand historical claims:

- `license_kind = pro`,
- `plan = pro`,
- `state = proActive` or `trial`,
- finite `exp`,
- explicit feature claims.

This compatibility exists only so previously verified fixtures or installations can be handled safely. The new Lifetime activation coordinator must reject a newly returned legacy subscription/trial token even if its cryptographic signature is otherwise valid.

No new checkout, email, MyPage, renewal, billing webhook, or marketing flow may issue those legacy products.

## 7. Device identity and one-device policy

The client device id is a random UUID persisted locally. It is not derived from clipboard data. Raw serial numbers or unnecessary private hardware identifiers are not required for the initial contract.

The service maintains an activation ledger:

```text
license_id
active_device_id
activated_at
deactivated_at
status
```

Activation rules:

- no active device: bind the requesting device and issue a token,
- same active device: allow idempotent reactivation and issue a valid token,
- different active device: reject until MyPage deactivation releases the slot,
- revoked/refunded license: reject.

MyPage deactivation clears the server-side active slot. The same license code may then activate another Mac.

### Offline limitation

A non-expiring offline token cannot be forcibly erased from a Mac that never reconnects. Therefore the one-active-device ledger is strictly authoritative for new activations, while an old permanently offline installation may continue to verify its already-issued token locally. This is an explicit trade-off favoring reliable lifetime/offline use for a low-cost product.

A future online status check, activation-generation claim, or renewable device lease may tighten remote revocation. Such a change must not introduce subscription billing or silently lock out legitimate Lifetime users during ordinary network outages.

## 8. MyPage requirements

MyPage must provide:

- purchased Board-Man Lifetime license listing,
- masked-by-default code display,
- explicit reveal/copy action,
- active device label and activation time,
- deactivate-current-device action,
- immediate slot reuse after successful deactivation,
- recent audit-safe license/device activity,
- support recovery path,
- rate limiting that does not trap normal hardware replacement.

The code remains the same across device transfers.

## 9. Local storage and bootstrap

The client stores only a verified signed token. The raw license code should not be persisted unless a later explicit secure-storage requirement is approved.

On launch:

1. load the stored signed token,
2. verify signature and Lifetime claims,
3. verify local device and bundle binding,
4. restore the Lifetime entitlement snapshot,
5. fall back to Free-safe behavior if verification fails.

Temporary network failure must not disable a previously verified Lifetime token.

## 10. Private service responsibilities

The private service owns:

- payment-success authority,
- idempotent order processing,
- cryptographically random license-code generation,
- hashed code lookup/storage where practical,
- customer/order/license association,
- one-device activation ledger,
- ES256 signing,
- transactional email delivery,
- MyPage license/device actions,
- admin lookup/reissue/revoke/recovery tools,
- refund/revocation policy,
- abuse/rate-limit controls,
- audit events that exclude clipboard data.

## 11. Security and privacy acceptance

- private signing key absent from the public client,
- activation request contains exactly four allowed fields,
- clipboard data absent from every licensing request,
- only verified Lifetime tokens are persisted by new activation,
- invalid signature/device/bundle/claim tokens are rejected,
- device transfer uses the same code,
- no subscription state or recurring-payment check is required,
- local paste/search startup does not depend on service reachability after activation.
