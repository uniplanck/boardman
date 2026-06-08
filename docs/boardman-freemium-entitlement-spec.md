# Board-Man Freemium Entitlement Spec

## LicenseState

```swift
enum LicenseState {
    case free
    case trial
    case proActive
    case proExpired
    case invalid
    case offlineGrace
    case locked
}
```

## Entitlement Shape

```swift
struct Entitlement {
    let plan: Plan
    let features: Set<Feature>
    let limits: EntitlementLimits
    let license: LicenseMetadata?
}
```

Required fields:

- `plan`: free, trial, pro, or locked plan category
- `features`: granted capabilities such as `pasteAnalytics` or `advancedAppearance`
- `limits`: numeric limits applied to history, pinned items, snippets, and folders
- `license metadata`: activation state, license id, device binding id, expiry, validation timestamp, and offline grace expiry when applicable

## Free Limits

- `maxHistoryItems`: 100
- `maxPinnedItems`: 3
- `maxSnippetItems`: 5
- `maxSnippetFolders`: 1 or 2

## Pro Features

- `unlimitedHistory`
- `unlimitedSnippets`
- `advancedAppearance`
- `exportImport`
- `pasteAnalytics`
- `futureSync`

## EntitlementGate Rule

UI lock is not enough. Every Pro-only execution path must go through `EntitlementGate` before performing the action.

Examples:

- Creating a sixth snippet must be blocked by entitlement logic, not only by a disabled button.
- Export/import must verify entitlement before file operations begin.
- Advanced appearance settings must not be applied from stored preferences unless entitlement allows them.
- Paste analytics views must verify entitlement before reading or presenting analytics data.

## Anti-Patterns

- `UserDefaults isPro=true`
- Local JSON `plan=pro`
- Plaintext license key storage
- UI-only lock
- Permanent offline Pro
- Private key inside binary

## Storage and Validation Direction

License keys should be stored through a secure local mechanism such as Keychain. Public verification material may ship with the app, but private signing keys must never be committed, displayed, or embedded in the binary.

Offline grace is temporary and must have an expiry. Expired, invalid, locked, and unknown states must fall back to Free-safe behavior unless a verified entitlement is present.
