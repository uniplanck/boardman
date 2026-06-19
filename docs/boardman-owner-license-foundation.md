# Board-Man Owner Lifetime License Foundation

This foundation adds structural support for an Owner Lifetime entitlement without shipping a usable owner bypass.

## Safe Future Flow

1. A trusted issuer creates a signed owner token outside the app.
2. The app verifies that token locally with a bundled public key.
3. Verification checks the token kind, subject, issue time, lifetime flag, bundle id, and device binding.
4. Only a verified token is stored in Keychain.
5. The central entitlement model maps the verified token to `ownerLifetime`.
6. `EntitlementGate` treats `ownerLifetime` as Pro-or-better.

## Token Shape

Future owner tokens should include:

- license kind or plan, such as `ownerLifetime`
- issued subject, such as `issued_to` or `sub`
- device binding claim, such as `device_id`
- issued timestamp, such as `iat`
- nullable expiry or explicit lifetime flag, such as `exp` and `is_lifetime`
- token version and key id for rotation

The app must not include private signing keys or hardcoded valid owner tokens.

## Storage

Owner token storage remains a Keychain-only future step. UserDefaults, local JSON, or plain text files must not become entitlement sources.

## Forbidden Shortcuts

- `UserDefaults isPro`
- email match
- device name match
- hardcoded admin key
- plain local JSON `owner=true`
- debug override that grants Pro in normal builds
- unsigned local token that unlocks Pro
