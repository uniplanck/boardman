# Board-Man QA Checklist

Use this checklist for local Board-Man panel, paste, and focus verification. Do not log clipboard contents. Record only pass/fail, delay, double paste, and focus restore observations.

## Build

```bash
xcodebuild -project "Board-Man.xcodeproj" -scheme "Board-Man" -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/BoardManPublicBuild -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO build
```

## Install

```bash
./scripts/boardman/install-dev-stable.sh
```

## Permissions

- Grant Accessibility manually if prompted.
- Grant Input Monitoring manually if prompted.
- Do not reset TCC during this checklist.

## Panel UI

| area | action | expected behavior | result | notes |
|---|---|---|---|---|
| tabs | open Board-Man panel | tabs show History, Pinned, Snippets, Favorites |  |  |
| History | select History tab | history items are shown |  |  |
| Pinned | select Pinned tab | pinned history/snippet items are shown |  |  |
| Snippets | select Snippets tab | snippet items are shown |  |  |
| Favorites | select Favorites tab | favorite/pinned workflow items are shown |  |  |
| search | type in search field | filtering applies only to active tab |  |  |
| search placeholder | focus empty search field | placeholder is Board-Man oriented and current |  |  |
| row hover | move pointer over rows | hover state is soft and readable |  |  |
| row selection | move keyboard selection | selection state is soft and readable |  |  |
| paste | press Enter on selected row | selected item pastes once |  |  |
| paste | click row | selected item pastes once |  |  |
| preferences | open Preferences | toolbar labels are Board-Man oriented |  |  |

## Paste Targets

| target app | action | expected behavior | result | notes | delay | double paste | focus restore |
|---|---|---|---|---|---|---|---|
| Chrome | paste one selected item | item pastes once into active field |  |  |  |  |  |
| Brave | paste one selected item | item pastes once into active field |  |  |  |  |  |
| Safari | paste one selected item | item pastes once into active field |  |  |  |  |  |
| VS Code | paste one selected item | item pastes once into editor |  |  |  |  |  |
| Cursor | paste one selected item | item pastes once into editor |  |  |  |  |  |
| Terminal | paste one selected item | item pastes once at prompt |  |  |  |  |  |
| Google Docs | paste one selected item | item pastes once into document |  |  |  |  |  |
| Notion | paste one selected item | item pastes once into active block |  |  |  |  |  |
| Slack or Discord | paste one selected item | item pastes once into message box |  |  |  |  |  |
| Finder | paste one selected item | no unsafe duplicate action occurs |  |  |  |  |  |
| IME composing | paste while IME composition is active | composition is not corrupted unexpectedly |  |  |  |  |  |
| full-screen app | paste into full-screen target | target remains usable after paste |  |  |  |  |  |
| multi-display | paste into app on secondary display | panel and focus behavior remain correct |  |  |  |  |  |
| sleep/wake | paste after sleep and wake | app still responds without duplicate paste |  |  |  |  |  |
