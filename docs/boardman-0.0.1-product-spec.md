# Board-Man 0.0.1 Product Spec

## Product Definition

Board-Man is a macOS menu-bar resident utility for clipboard-heavy work. It keeps clipboard history, snippets, paste count visibility, appearance customization, productivity shortcuts, backup/export, license and Pro entitlement, Sparkle/GitHub Releases update flow, and future sync, team, and cloud features under one product direction.

The 0.0.1 baseline resets the product from the earlier 1.2.3 experimental phase into a formal product foundation.

## Canonical Identity

- Canonical app name: Board-Man
- Canonical bundle id: `com.uniplanck.BoardMan`
- Release channel: internal / pre-release until explicitly released
- Version baseline: `CFBundleShortVersionString = 0.0.1`, `CFBundleVersion = 1`

## Completion Condition

Board-Man 0.0.1 is complete when the repository defines the product baseline, freemium entitlement model, premium dark design system, release/update architecture, and version metadata without changing runtime behavior, production distribution settings, private keys, backend services, notarization, or release publishing.

## Included Scope

- Existing stable Clipboard History
- Basic Snippets
- Board-Man item paste count
- Manual Cmd+V paste count only when the target is editable/input-like
- No count for right-click paste
- No count for Edit > Paste
- Basic Free / Pro entitlement design
- Basic License screen design/spec
- Updates tab and manual update check route
- Premium Dark UI minimum direction
- No production appcast publishing

## Excluded Scope

- Cloud sync
- Team features
- Full license backend
- Production appcast
- GitHub Release asset upload
- Sparkle private signing key generation, display, or commit
- Notarization
- Right-click paste count
- App-internal git pull + local build update

## Free / Pro Philosophy

Free should be useful for everyday clipboard history, light snippets, and evaluation. Pro should unlock scale, advanced customization, analytics, backup/export, and future connected workflows.

Locked Pro functionality must remain visible enough to explain value, but disabled until entitlement allows execution. A UI lock alone is not sufficient; execution paths must also enforce entitlement.

## Version Reset Path

Version metadata is localized in the app and test bundle Info.plist files for this baseline. Future release automation should keep `CFBundleShortVersionString`, `CFBundleVersion`, GitHub tag naming, and Sparkle appcast metadata aligned from a single release checklist or script.
