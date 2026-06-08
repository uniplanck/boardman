# Board-Man Freemium License Design

## Product Definition

Board-Man is a local-first macOS clipboard productivity app derived from Clipy. It focuses on fast clipboard history, snippets, paste visibility, hotkeys, and dense customization for people who repeatedly move text, URLs, commands, and images across apps.

The freemium model keeps the app useful without payment while reserving advanced customization, larger limits, and workflow power features for Pro.

## Sales And Download Flow

uniplanck.com is the source of truth for product positioning, downloads, purchase, license management, and support.

1. Visitor lands on the Board-Man product page on uniplanck.com.
2. Visitor compares Free and Pro features.
3. Visitor downloads the macOS app without requiring an account.
4. Free users can keep using the local Free plan.
5. Pro buyers purchase on uniplanck.com and receive a license key.
6. The app activates the license through the uniplanck.com license API.
7. License management on uniplanck.com supports device reset, deactivation, and support recovery.

## Free Vs Pro Matrix

| Area | Free | Pro |
| --- | --- | --- |
| Clipboard history | 100 history items | Unlimited history |
| Pins | 3 pinned items | Unlimited pinned items |
| Snippets | 5 snippets | Unlimited snippets |
| Search | Standard local search | Advanced workflow options where applicable |
| Paste count | Basic visibility | Full paste analytics and sorting controls |
| Appearance | Core theme controls | Fine-grained appearance customization |
| Hotkeys | Essential hotkeys | Extended hotkey customization |
| Export/import | Limited or unavailable | Full backup and migration features |
| License support | Free local state | Activated license, recovery, deactivation |

Exact limits should be defined in the entitlement table, not hardcoded across UI files.

Internal founder lifetime codes are for maintainer dogfooding only. The full founder code must not be committed; the app only contains the SHA256 hash used for local verification. Production licensing still requires signed token activation through a backend.

## LicenseState

- `free`: no active paid entitlement; Free features available.
- `trial`: temporary Pro entitlement with an expiry date.
- `proActive`: verified paid entitlement; Pro features available.
- `proExpired`: paid entitlement exists but subscription or validity has expired.
- `invalid`: license token or key failed verification.
- `offlineGrace`: previously verified Pro license is temporarily trusted offline.
- `locked`: feature is unavailable under the current entitlement.

## Entitlement Model

Entitlements should be represented as one centralized local model:

- `plan`: `free`, `trial`, or `pro`.
- `features`: named capabilities such as `appearanceAdvanced`, `extendedHotkeys`, `exportImport`, and `unlimitedSnippets`.
- `limits`: numeric caps such as history count, snippet count, saved searches, or theme preset count.
- `license metadata`: license id, issued at, expires at, device id, status, token version, revocation marker, last verified at, and grace expiry.

UI and execution paths must ask the entitlement gate instead of duplicating license checks.

## One License Equals One PC

One Pro license activates one Mac at a time. A second Mac requires either a second license or a deactivation/reset of the first device through supported recovery flows.

Device transfer should be explicit, auditable, and rate limited on the server.

## Device Identity Strategy

Device binding should combine stable local identity and verifiable app context without storing sensitive raw identifiers.

- `localDeviceId`: random UUID generated on first launch.
- Keychain stored id: store `localDeviceId` in Keychain, not in UserDefaults.
- Machine fingerprint hash: optional salted hash of stable machine attributes, never raw hardware identifiers.
- Bundle id: include expected Board-Man bundle id in signed claims.
- App signature context: include app signing context or team id where practical to reduce token replay across modified apps.

The device identity must survive app relaunches and normal updates, but support reset through a deliberate recovery path.

## Activation Flow

1. User enters license key in Board-Man Preferences.
2. Board-Man sends license key, `localDeviceId`, app version, bundle id, and signature context to the uniplanck.com license API.
3. The API validates the key, device count, revocation status, and product entitlement.
4. The API returns a signed license token with entitlement claims.
5. Board-Man verifies the token locally with an embedded public key.
6. The verified token is stored locally in Keychain or protected app storage.
7. The centralized entitlement gate unlocks Pro features.

The private signing key must never be embedded in the app.

## Deactivation And Reset Support

Supported flows:

- In-app deactivate: removes the local token and informs the license API.
- Web reset: user resets the bound device on uniplanck.com after sign-in or support verification.
- Support reset: manual recovery path with audit logging.

Reset should invalidate the previous device binding and require reactivation.

## Offline Grace Policy

Board-Man should continue Pro access during short offline periods after a successful activation.

Recommended policy:

- Allow `offlineGrace` for a bounded period, for example 7 to 14 days after last successful verification.
- Keep grace expiry inside the signed token or a locally protected verification record.
- Show a non-blocking warning before grace expiry.
- Downgrade to `proExpired` or `invalid` when grace is exhausted or token verification fails.

## Anti-Tamper Layers

No single local layer is enough. Use layered friction:

- Signed token.
- Public key verification.
- Keychain storage for device id and token.
- Device binding.
- Server-side revocation.
- Centralized entitlement gate.
- Execution-level gates for Pro behavior.
- UI lock consistency.
- Debug override isolation from release builds.
- Audit logs for activation, deactivation, reset, and suspicious transitions.

## Limitation

Local Mac apps cannot be made fully uncrackable. The realistic goal is to protect honest licensing, make casual bypasses difficult, keep server-side entitlements authoritative, and avoid fragile checks that break legitimate users.

## Anti-Patterns

Avoid:

- `UserDefaults isPro=true`.
- Local JSON pro flag only.
- UI-only lock with execution paths still enabled.
- Plaintext license key storage.
- Embedded private key.
- Scattered entitlement checks across random controllers.
- Debug unlocks compiled into production builds.

## Rollout Phases

1. Document licensing, design system, and implementation boundaries.
2. Add local entitlement model with Free defaults only.
3. Add UI and execution gates without payment or server calls.
4. Add License Preferences UI mock.
5. Add Keychain device id and signed-token verification stub.
6. Integrate uniplanck.com license API.
7. Add activation, deactivation, reset, and offline grace.
8. Add hardening, audit logging, and release QA.
9. Connect uniplanck.com landing page, download, purchase, and support flows.
