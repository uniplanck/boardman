# Board-Man LP Free Vs Pro Design Spec

## Purpose

This document is the implementation handoff for a future Board-Man landing page on uniplanck.com. It is docs-only for this PR because this repository does not contain the production uniplanck.com landing page implementation target.

Do not deploy uniplanck.com from this work. Do not change Board-Man app behavior from this spec alone.

## Page Goals

- Make Free download immediately available without account creation.
- Explain why Pro exists without weakening the Free product.
- Keep Free vs Pro limits consistent with the licensing entitlement model.
- Reuse the Board-Man product visual language from the app design system.
- Keep production licensing clearly server-backed with signed tokens.

## Hero Section

The first viewport should identify Board-Man as a local-first macOS clipboard productivity app.

Required content:

- Product name: Board-Man.
- Short positioning: clipboard history, snippets, paste visibility, and customization for repeated copy/paste work.
- Primary CTA: Free Download.
- Secondary CTA: Upgrade to Pro or View Pro.
- Visual: product screenshot or the Free vs Pro LP visual reference.
- Trust note: local-first macOS utility.

Recommended hero structure:

- Dark charcoal background using the shared tokens.
- Product screenshot or LP section image as the main visual.
- Primary CTA uses the red accent only if it remains visually distinct from the Pro CTA; otherwise use red for Pro and a neutral high-contrast button for Free Download.
- Avoid marketing-only imagery that does not show the product.

## Calls To Action

### Free Download CTA

Behavior:

- Links to the current Board-Man macOS download path.
- Does not require an account.
- Copy should make clear that Free remains usable locally.

Suggested labels:

- `Free Download`
- `Download for macOS`

### Upgrade To Pro CTA

Behavior:

- Links to future uniplanck.com purchase or checkout flow.
- Should not imply Pro activation is local-only.
- Should point users toward account/license management when that backend exists.

Suggested labels:

- `Upgrade to Pro`
- `Get Pro`

## Free Vs Pro Comparison

Use this as the landing page comparison baseline. Exact numeric limits should stay aligned with the centralized entitlement table.

| Area | Free | Pro |
| --- | --- | --- |
| Clipboard history | 100 history items | Unlimited history |
| Pins | 3 pinned items | Unlimited pinned items |
| Snippets | 5 snippets | Unlimited snippets |
| Search | Standard local search | Advanced workflow options where applicable |
| Paste visibility | Basic paste count visibility | Full paste analytics and sorting controls |
| Appearance | Core theme controls | Fine-grained appearance customization |
| Hotkeys | Essential hotkeys | Extended hotkey customization |
| Export/import | Limited or unavailable | Full backup and migration features |
| License support | Free local state | Activated license, recovery, deactivation |

Comparison design rules:

- Free should look credible, not hidden.
- Pro should be clearly stronger but not framed as required for basic clipboard use.
- Locked Pro features may be previewed, but the page must not promise app behavior before entitlement gates exist.
- Keep copy consistent with `docs/freemium-license-design.md`.

## Licensing Copy Requirements

Required copy constraints:

- One Pro license activates one PC/Mac at a time.
- Device transfer requires deactivation, reset, or support recovery.
- Founder Lifetime is internal dogfooding only.
- Do not expose or publish the founder code body.
- Production licensing still requires signed token activation through a backend.
- The private signing key must never be embedded in the app.

Recommended customer-facing wording:

> One Pro license activates one Mac at a time. You can move a license through supported deactivation or reset flows.

Internal-only wording:

> Founder Lifetime codes are for maintainer dogfooding only and are not part of the public landing page offer.

## Visual Asset Mapping

Use repo assets when implementing docs previews or future local design references. The local Downloads paths are source references only and should not be hardcoded in production pages.

| Reference | Local source | Repo asset path | Intended use |
| --- | --- | --- | --- |
| Free vs Pro LP section | `/Users/naomac/Downloads/Board-Man画像/Board-Man_Free_vs_Pro_LP_Section.png` | `docs/assets/boardman-freemium-design/Board-Man_Free_vs_Pro_LP_Section.png` | Landing page comparison layout reference |
| Full design system sheet | `/Users/naomac/Downloads/Board-Man画像/Board-Man_Full_Design_System_Sheet.png` | `docs/assets/boardman-freemium-design/Board-Man_Full_Design_System_Sheet.png` | Token and component direction |
| License Free state UI | `/Users/naomac/Downloads/Board-Man画像/Board-Man_License_Freemium_Free_State_UI.png` | `docs/assets/boardman-freemium-design/Board-Man_License_Freemium_Free_State_UI.png` | License tab Free state reference |
| Pro locked control pattern | `/Users/naomac/Downloads/Board-Man画像/Board-Man_Pro_Locked_Control_Pattern.png` | `docs/assets/boardman-freemium-design/Board-Man_Pro_Locked_Control_Pattern.png` | Locked Pro control reference |

## Design Tokens For uniplanck.com

Reuse the app design system direction from `docs/boardman-ui-design-system.md`.

Core tokens:

| Token | Value | LP use |
| --- | --- | --- |
| `color.bg.app` | `#151515` | Page background |
| `color.bg.panel` | `#1E1E1E` | Comparison and feature sections |
| `color.bg.panelAlt` | `#252525` | Table rows, secondary surfaces |
| `color.border.subtle` | `#343434` | Dividers and table borders |
| `color.text.primary` | `#F2F2F2` | Headings and primary copy |
| `color.text.secondary` | `#B8B8B8` | Body copy |
| `color.text.muted` | `#7D7D7D` | Disabled or helper copy |
| `color.accent.red` | `#FF3B30` | Pro CTA, badges, accents |
| `color.accent.redHover` | `#FF5148` | CTA hover |

Layout rules:

- Keep comparison sections dense and scannable.
- Use 8 px or smaller radius for panels and cards.
- Avoid nested cards.
- Use real app screenshots or product UI references, not abstract illustrations.
- Keep Free Download visible above the fold.

## Future uniplanck.com Implementation Handoff

Recommended implementation sequence:

1. Add a Board-Man product route on uniplanck.com.
2. Implement hero with Free Download and Upgrade to Pro CTAs.
3. Add Free vs Pro comparison from this document.
4. Wire Free Download to the current release download path.
5. Wire Upgrade to Pro to the production purchase flow only after backend licensing exists.
6. Add license management copy after deactivation/reset support is implemented.
7. Validate visual consistency against the asset references and design tokens.

Backend dependencies before production Pro sales:

- License purchase flow.
- Signed license token issuing service.
- Device binding for one license equals one PC.
- Deactivation and reset support.
- Server-side revocation and support recovery.

Until those exist, the landing page may describe the intended Pro direction but must not sell a production Pro license.
