# Board-Man Owner Lifetime License

Board-Man supports a local Owner Lifetime entitlement without embedding a reusable bypass in the app.

## Implemented Flow

1. `scripts/boardman/owner-license-tool.swift bootstrap-key` creates a P-256 issuer private key in this Mac's Keychain.
2. Only the corresponding public key is compiled into Board-Man.
3. The stable installer creates a signed, device-bound Owner Lifetime token after the canonical app is installed and signed.
4. The signed token and local device id are stored with owner-only file permissions under `~/Library/Application Support/com.uniplanck.BoardMan/`.
5. At launch, Board-Man verifies the signature, algorithm, license kind, plan, state, lifetime flag, token version, bundle id, and local device id.
6. Only a successfully verified token is mapped to `ownerLifetime` through `EntitlementService` and `EntitlementGate`.
7. Any missing, malformed, unsupported, expired, mismatched, or invalid token fails closed to Free.

## Token Claims

The local owner token contains:

- `license_id`
- `license_kind = ownerLifetime`
- `plan = ownerLifetime`
- `state = ownerLifetime`
- enabled entitlement features
- `issued_to` and `sub`
- `iat`
- `is_lifetime = true`
- `device_id`
- `bundle_id = com.uniplanck.BoardMan`
- `token_version = 1`

It has no expiry claim. Lifetime access still requires a valid signature and the matching device and bundle identity.

## Local Storage

- Issuer private key: Keychain only; never committed or embedded in the app.
- Local device id: `Application Support/com.uniplanck.BoardMan/device-id`, mode `0600`.
- Signed license token: `Application Support/com.uniplanck.BoardMan/owner-license.jwt`, mode `0600`.
- Public verification key: embedded in the app.
- UserDefaults entitlement fields: diagnostics only and never read as an entitlement source.

The token and device id are not secrets. Authorization depends on the P-256 signature plus device and bundle claims, so editing or replacing either file fails closed to Free. Keeping them outside Keychain prevents local self-signed development builds from showing a password confirmation after every rebuild.

## Automatic Application

`scripts/boardman/install-dev-stable.sh` preserves an existing verified local token without reading Keychain. The issuer private key is accessed only when a new token must be generated. Existing Keychain token and device-id entries are migrated once for compatibility. Other Macs do not silently generate an owner issuer key and remain on the normal Free path.

Run the non-secret status check with:

```bash
scripts/boardman/status-tcc-friendly.sh
```

The expected local owner result is:

```text
Entitlement Diagnostic: verified / ownerLifetime
```

## Forbidden Shortcuts

- `UserDefaults isPro`
- email or device-name matching
- hardcoded valid license key
- plain local JSON `owner=true`
- unsigned local token
- debug override in normal builds
- private signing key in source, app resources, logs, or diagnostics
