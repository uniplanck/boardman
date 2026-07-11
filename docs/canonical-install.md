# Canonical Board-Man Install

Board-Man has one canonical local identity:

- App path: `/Applications/Board-Man.app`
- Bundle identifier: `com.uniplanck.BoardMan`
- Bundle name: `Board-Man`
- Local signing identity: `Board-Man Local Developer`

Do not run or register copies such as `Board-Man-beta.app`, `Board-Man 2.app`, DerivedData products, or backup `.app` bundles. Multiple app bundles pollute Finder/Spotlight and LaunchServices and make macOS Accessibility and Input Monitoring grants difficult to preserve.

## Stable Local Install

Use:

```bash
scripts/boardman/install-dev-stable.sh --configuration Release
```

The helper:

- builds an arm64 Release app for the current Apple Silicon Mac
- enables dead-code and product stripping
- backs up the previous canonical app under a `.noindex` cache
- replaces only `/Applications/Board-Man.app`
- signs the app with the same local certificate identity every time
- verifies the signature and bundle id
- removes quarantine/provenance attributes when present
- restores the local Owner Lifetime token when the issuer key exists
- unregisters stale LaunchServices copies
- preserves `BoardManUsePanelUI`
- reopens the canonical app

It intentionally refuses to fall back to ad-hoc signing. Ad-hoc signatures change identity across builds and commonly trigger repeated TCC permission prompts.

## Build Artifact Cleanup

Old build products can be archived without deletion using:

```bash
scripts/boardman/archive-local-build-copies.sh
```

The script moves old Board-Man DerivedData and `_copy` app bundles into `.noindex` archives, unregisters them from LaunchServices, and renames archived app payloads so Finder does not treat them as runnable Board-Man copies.

## TCC Boundary

The install scripts never run `tccutil reset` and never modify the TCC database. The first Accessibility or Input Monitoring approval remains a manual macOS action.

Stable certificate signing, the canonical bundle id, and the canonical install path substantially reduce permission churn, but changing or deleting the local signing certificate can still require approval again.

## Diagnostics

Run:

```bash
scripts/boardman/status-tcc-friendly.sh
```

The status helper verifies:

- installed path and bundle id
- app size and architecture
- certificate signature
- TCC identity risk
- running process
- signed license token presence and verified plan diagnostic
- Finder/Spotlight duplicate app bundles
