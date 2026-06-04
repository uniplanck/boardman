# Board-Man Freemium Next Codex Tasks

## Entitlement Core Only

- Scope: add local entitlement types, Free defaults, and centralized query API.
- Forbidden changes: no payment API, no production license calls, no Realm schema change, no user data migration.
- Likely files: license or app service model files, lightweight tests if present.
- Validation: unit-level checks or compile validation for entitlement defaults.
- Completion condition: app can query Free entitlements through one gate.

## License UI Mock Only

- Scope: add License Preferences tab mock for local states.
- Forbidden changes: no network calls, no activation side effects, no secret storage.
- Likely files: Preferences UI files, local preview/mock state files.
- Validation: render Free, Trial, Pro Active, Pro Expired, Invalid, Offline Grace, and Locked.
- Completion condition: UI shows states but does not change production behavior.

## Pro Lock Controls Only

- Scope: create reusable locked Pro control pattern for Preferences.
- Forbidden changes: no entitlement backend rewrite, no payment flow, no production license calls.
- Likely files: Preferences shared controls, style helpers.
- Validation: locked controls are disabled and visually consistent.
- Completion condition: one or more controls use the reusable Pro lock pattern.

## Appearance Design-System Polish Only

- Scope: align Appearance tab with the design-system tokens and layout rules.
- Forbidden changes: no licensing logic, no storage migration, no unrelated Preferences tabs.
- Likely files: Appearance Preferences UI files and shared style tokens.
- Validation: visual inspection plus existing build if required.
- Completion condition: Appearance tab follows dark premium utility direction.

## Keychain Device ID Only

- Scope: generate and persist `localDeviceId` in Keychain.
- Forbidden changes: no machine fingerprinting beyond stub planning, no license activation, no production API.
- Likely files: Keychain helper, license identity service, tests if present.
- Validation: id persists across relaunch and is not stored in UserDefaults.
- Completion condition: stable local device id is available to future activation code.

## Signed Token Verification Stub Only

- Scope: add local token model and public-key verification interface with stubbed fixtures.
- Forbidden changes: no private key in app, no production API, no Pro unlock by raw local flag.
- Likely files: license token model, verifier service, test fixtures.
- Validation: valid fixture passes, invalid signature or expired fixture fails.
- Completion condition: entitlement gate can consume a verified-token result.

## uniplanck.com License API Integration Only

- Scope: integrate approved license API for activation and verification.
- Forbidden changes: no payment API implementation, no embedded secrets, no debug unlock in release, no force reset of user data.
- Likely files: API client, activation view model, license service, error mapping.
- Validation: mocked API tests, staging validation when available, no secrets printed.
- Completion condition: activation returns a signed token and local verification unlocks Pro.
