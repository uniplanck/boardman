# Board-Man Design System

## Direction

Board-Man uses a Premium Dark macOS Utility direction: dark charcoal surfaces, red accent, thin borders, rounded cards, dense but readable preferences, live-preview-oriented appearance controls, and visible disabled Pro controls.

The UI should feel like a resident productivity utility, not a marketing page. Preferences should prioritize scanning, comparison, and repeated adjustment.

## Color Tokens

- `background.base`: `#0E0F11`
- `background.window`: `#151619`
- `background.panel`: `#1C1D20`
- `background.card`: `#202226`
- `background.field`: `#141518`
- `border.subtle`: `#2B2D31`
- `border.normal`: `#3A3D42`
- `border.active`: `#FF4B4B`
- `text.primary`: `#F2F2F3`
- `text.secondary`: `#B7B8BC`
- `text.muted`: `#777A80`
- `accent.red`: `#FF4B4B`
- `accent.red.deep`: `#B91F2B`
- `accent.red.soft`: `#3A1518`

## Radius Tokens

- `radius.window`: 18
- `radius.panel`: 12
- `radius.card`: 10
- `radius.control`: 7
- `radius.pill`: 999

## Preferences Target Structure

- General
- Hotkeys
- Snippets
- Appearance
- Advanced
- License
- Updates

## Appearance Target Sections

- Window Background
- Source
- Appearance Adjustments
- Window Shape & Layout
- Behavior & Interaction
- Quick Presets
- Live Preview

## License Target Sections

- Current Plan
- License Key Activation
- Device Binding
- Pro Features
- CTA

## Pro Locked Control Pattern

Pro controls should remain visible but disabled. The pattern is:

- Visible control
- Disabled interaction
- Lock icon
- Pro pill
- Value preview
- Click opens upgrade sheet

Locked controls should show what value or option would be available with Pro without applying it. Unlocking must still depend on entitlement execution checks, not only the visual state.
