# Board-Man Free / Lifetime Entitlement Spec

Status: authoritative client entitlement contract
Updated: 2026-08-27
Source of truth: `docs/boardman-commercial-lifetime-roadmap.md`

## 1. Product model

Board-Man has exactly two public product states:

- **Free**
- **Lifetime**

There is no subscription product, recurring billing entitlement, paid trial, renewal, or version-based repurchase requirement in the approved commercial model.

Existing `trial`, `proActive`, `proExpired`, and `offlineGrace` values may remain parseable temporarily so old signed-token fixtures and compatibility tests do not break. They are legacy protocol states, not new products.

## 2. Central policy

All numeric and product-policy constants are owned by `BoardManCommercialPolicy`.

```swift
enum BoardManCommercialPolicy {
    static let freeHistoryItems = 100
    static let freePinnedItems = 3
    static let freeSnippetItems = 5
    static let freeSnippetFolders = 1
    static let lifetimeDeviceLimit = 1
    static let supportsSubscription = false
    static let lifetimeIncludesFutureAppVersions = true
}
```

These values must not be duplicated as unrelated magic numbers in UI controllers or services.

## 3. Free contract

Free retains the core clipboard product:

- clipboard capture and normal paste,
- basic search,
- basic hotkeys,
- privacy and application-exclusion controls,
- data integrity and recovery,
- export and import,
- security, reliability, and application updates.

Initial Free limits:

| Resource | Limit |
| --- | ---: |
| History | 100 |
| Pinned items | 3 |
| Templates/snippets | 5 |
| Template/snippet folders | 1 |

Crossing a limit must not delete, rewrite, hide permanently, or corrupt existing data. Existing over-limit data remains readable and exportable. A quota may reject a new addition or constrain future retention only after an explicit non-destructive rollout policy is implemented and tested.

## 4. Lifetime contract

Lifetime is a one-time purchase. It provides:

- unlimited history,
- unlimited pins,
- unlimited Templates/snippets,
- unlimited Template/snippet folders,
- advanced appearance,
- local paste analytics,
- advanced local search,
- workflow actions,
- Template variables,
- workspace/session features,
- advanced timed-pin behavior,
- future local paid Board-Man features unless explicitly documented otherwise.

A valid Lifetime license remains valid across future Board-Man application versions. New local Lifetime features must not require customers to receive a newly issued license merely because the original token predates a feature identifier.

Lifetime does not automatically include perpetual third-party or server operating-cost services such as AI inference, cloud storage, team infrastructure, or external APIs. Those capabilities require an explicit future service contract.

## 5. Device contract

- one license allows one active device at a time,
- the same license code is reused after deactivation,
- MyPage is the normal device-deactivation authority,
- after deactivation, the activation slot becomes available to another Mac,
- hardware replacement does not require a new license purchase or new code.

The client stores a stable random local device ID. It must not derive device identity from clipboard contents or expose raw private hardware identifiers unnecessarily.

## 6. Feature access models

Every feature belongs to one access model.

### Free local

Available without a license:

- `exportImport`

### Lifetime local

Automatically available to a valid Lifetime entitlement:

- `unlimitedHistory`
- `unlimitedSnippets`
- `advancedAppearance`
- `pasteAnalytics`
- `advancedSearch`
- `workflowActions`
- `templateVariables`
- `workspaceSessions`
- `advancedTimedPins`

For Lifetime, the entitlement state itself is sufficient for future local Lifetime features. An old token does not need every future feature string embedded in its original claim set.

### Service-backed

Never implied solely by Lifetime. These require an explicit signed service claim or a later approved contract:

- `futureSync`
- `cloudBackup`
- `aiAssist`
- `teamSharing`
- `accountServices`
- `apiAccess`
- `commercialSupport`

## 7. Runtime gate rules

`EntitlementGate` is the central client decision boundary.

Required behavior:

- Free returns limits `100 / 3 / 5 / 1`.
- Lifetime returns unlimited limits.
- Free can use Free-local features.
- Free cannot use Lifetime-local features.
- Lifetime can use every Lifetime-local feature, including features introduced after token issuance.
- Lifetime does not receive service-backed features unless explicitly claimed.
- Legacy verified Pro/trial tokens may continue to use exactly the features they claim while compatibility support exists.
- Invalid, expired, locked, or unverified states fall back to Free-safe behavior.

UI locks are not sufficient. Any operation that changes paid-only state must consult the execution-layer gate before mutation.

## 8. Non-destructive downgrade and migration

Changing from Lifetime or a legacy entitlement to Free must never remove user data automatically.

When an account is over a Free limit:

- existing items remain visible,
- existing items remain searchable where the base feature permits,
- export remains available,
- new additions may be blocked with a clear Lifetime purchase prompt,
- the app must not silently trim data merely because the entitlement changed.

History retention deserves a separate acceptance gate because current retention cleanup deletes old unpinned records. The Free history limit must not be wired into that deletion path until grandfathering and recovery behavior are explicitly implemented and tested.

## 9. Token compatibility

The public client verifies signed tokens using an embedded public key. Private signing material remains outside this repository.

New activation must accept only the Lifetime claim shape approved in the commercial service contract. Legacy subscription/trial claim parsing may remain isolated for backwards compatibility, but no new subscription purchase, renewal, billing polling, or grace-period product logic may be added.

## 10. Acceptance

Phase 1 closes when all are true:

- policy constants are exact,
- Free boundary tests pass,
- Lifetime local feature tests pass,
- future local feature compatibility is proven,
- service-backed isolation is proven,
- legacy token parsing remains bounded,
- user-facing product wording no longer describes the new offer as a subscription,
- focused tests and affected build pass,
- `git diff --check` passes.
