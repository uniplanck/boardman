# Board-Man Technical Excellence Master Plan

Status: authoritative roadmap; Phase 2 PASS / CLOSED, Phase 3 PASS / CLOSED, Phase 4 PASS / CLOSED, Phase 5 ACTIVE (P5.2/P5.3 PASS / CLOSED; P5.1 manual acceptance OPEN)
Created: 2026-08-21
Baseline refreshed: 2026-08-27
Execution rule: **Phase 0 is PASS / CLOSED. Phase 1 measurement remains active as non-blocking calibration work. Phase 2 persistence modernization is PASS / CLOSED. Phase 3 search and information retrieval (P3.1-P3.3) is PASS / CLOSED. Phase 4 structural decomposition, dependency reduction, and concurrency hardening is PASS / CLOSED. Phase 5 remains ACTIVE: P5.2 data integrity/recovery and P5.3 privacy are PASS / CLOSED; P5.1 automated coverage is PASS and real-application manual acceptance remains OPEN.**

## 1. Purpose

Board-Man should not merely be a feature-rich clipboard manager. The target is a macOS clipboard workspace that is simultaneously:

- extremely lightweight in idle and interactive use,
- fast under large histories,
- highly reliable for paste and shortcut workflows,
- structurally easy to understand and change,
- safe to migrate and recover,
- independent from the historical Clipy implementation,
- local-first by default,
- open-source for the local client while commercial value stays behind explicit service boundaries,
- easy to test, benchmark, release, update, and diagnose.

The roadmap optimizes for **measured user-visible quality**, not modernization for its own sake. Rewriting code, adding frameworks, adopting SwiftUI, or replacing storage is not success unless the resulting product is measurably smaller, faster, safer, clearer, or more capable.

## 2. Non-negotiable rules

1. **Finish current work before starting this roadmap.** Phase 0 is the only executable phase until its acceptance gate passes.
2. **No data-loss migrations.** Every persistence migration must be backed up, verified, recoverable, and tested with realistic legacy fixtures.
3. **No framework worship.** Replace a dependency only when the replacement lowers complexity, runtime cost, maintenance risk, or improves a required capability.
4. **Local features remain usable without a commercial license.** Paid value should primarily depend on private services such as sync, backup, AI, team, account, or API services.
5. **Performance claims require repeatable measurements.** Targets below are SLO candidates until Phase 1 records a baseline on fixed hardware and fixtures.
6. **One architectural owner per responsibility.** Clipboard capture, persistence, search, paste, hotkeys, templates, pins, licensing, and UI presentation must not be hidden inside a single coordinator.
7. **Compatibility code is temporary and isolated.** Legacy identifiers may exist only inside a clearly named migration/compatibility boundary and must not leak into normal product code.
8. **Release completion means installed-app completion.** Build, signing, installed `/Applications/Board-Man.app`, launch, version, executable path, and smoke tests are part of the normal done definition.

## 3. Current baseline snapshot

Fresh Phase 1 entry snapshot captured on 2026-08-24. Detailed evidence lives in `docs/boardman-phase1-baseline-snapshot.md` and the benchmark methodology in `docs/boardman-phase1-benchmark-methodology.md`.

### Accepted independent-core state

- Phase 0 Independent Core: PASS / CLOSED,
- historical Clipy-organization Swift package references in `Package.resolved`: `0`,
- CPY-named Swift source files: `0`,
- Board-Man-owned hotkey registry and shortcut recording layer introduced,
- login-at-launch moved to macOS `SMAppService`,
- screenshot observation moved to Board-Man implementation,
- `BoardManApplicationInfo`, `BoardManDragPayload`, and `BoardManRuntimeSupport` introduced,
- MIT-client / commercial-service entitlement boundary introduced,
- local feature limits removed from the commercial entitlement model,
- signed entitlement verification supports subscription/trial/owner-lifetime forms,
- Phase 0 full tests, Debug/Release build, codesign, installed-app smoke, compatibility and attribution gates passed,
- post-Phase-0 horizontal keyboard navigation now covers History → Templates All → persisted template groups.

Required upstream MIT attribution and explicitly isolated persistence/archive compatibility identifiers remain intentionally. Their presence is not evidence that normal product code still depends on an active CPY product type.

### Fresh measurable technical debt at Phase 1 entry

- Swift source/test files: `61`,
- production Swift files importing `RealmSwift`: `13`,
- direct production `Realm()` construction sites: `59`,
- persistence/domain/UI responsibilities remain coupled in places,
- `MenuManager` remains a very large coordinator and must eventually be decomposed,
- Release app footprint at Phase 1 entry: `36,088 KiB` by `du -sk`,
- Release main executable: `31,804,640` bytes,
- directly embedded top-level framework count: `1` (`Sparkle.framework`),
- production notarization / Sparkle release automation is not yet complete,
- the final Board-Man-native store architecture remains Phase 2 work.

Do not interpret Realm counts as permission to start the SQLiteData migration during Phase 1. Measure first.

## 4. North-star architecture

```text
macOS / AppKit UI
       |
       v
Presentation / View Models
       |
       v
Board-Man Domain Services
  |        |        |        |
History  Paste   Templates  Search
  |        |        |        |
  +--------+--------+--------+
               |
               v
         BoardManStore
          /       \
         /         \
 SQLiteData       PayloadStore
 metadata/index   images/files/blob payload
         |
         +---- FTS5 / indexed queries

System adapters beside the domain:
- PasteboardCapture
- HotKeyRegistry
- Accessibility/Input
- LaunchAtLogin
- UpdateService
- CommercialServiceClient

LegacyRealmImporter exists only at the migration edge and is removable.
```

### Intended module boundaries

The exact Xcode/SwiftPM module split should follow measured build/runtime value, but responsibilities should converge toward:

- `BoardManCore`: value types, domain rules, identifiers, normalization
- `BoardManStorage`: SQLiteData schema, repositories, migrations
- `BoardManClipboard`: pasteboard capture and payload normalization
- `BoardManPaste`: paste dispatch, target settling, post-paste actions
- `BoardManSearch`: FTS/index/ranking/query parsing
- `BoardManTemplates`: template/folder behavior
- `BoardManPins`: permanent and timed pin behavior
- `BoardManHotKeys`: key combo representation and registration
- `BoardManLicensing`: signed entitlement verification and commercial client contract
- `BoardManUI`: AppKit presentation and interaction
- `BoardManMigration`: one-way legacy importers and compatibility fixtures

Do not split into modules merely to increase module count. Split when the boundary makes ownership, tests, compile isolation, or dependency direction materially clearer.

# Phase 0 — Finish the current independent-core work

**Execution status: PASS / CLOSED. Phase 1 is unblocked.**

## P0.1 Clipy implementation independence

Complete the replacement of historical implementation code rather than renaming it cosmetically.

Required outcomes:

- replace remaining CPY domain/model types with Board-Man-native types,
- replace remaining CPY preferences/controllers/views where the implementation is inherited,
- replace historical service implementations that still contain upstream implementation logic,
- isolate any compatibility identifier strings inside migration-only code,
- remove historical XIB custom class/module references from normal runtime UI,
- rename Xcode target/module/build internals from `Clipy` to Board-Man-native naming when safe,
- rename the source directory structure after project references are stable,
- audit images/resources and replace inherited assets where necessary,
- final source-level search for Clipy/ClipMenu/CPY origin markers.

### P0 acceptance gate

Phase 0 cannot close until all are true:

- [ ] no distributed source file contains an active upstream implementation that Board-Man still depends on,
- [ ] historical identifiers exist only in explicitly documented legacy migration compatibility code, if required,
- [ ] Clipy-owned package dependencies: `0`,
- [ ] active CPY product types/classes: `0`,
- [ ] Xcode product target/module no longer identifies as Clipy,
- [ ] Debug build PASS,
- [ ] full tests PASS,
- [ ] Release build PASS,
- [ ] installed app smoke PASS,
- [ ] license/attribution audit completed,
- [ ] only after that audit, Board-Man-owned MIT LICENSE is promoted from draft where legally appropriate.

## P0.2 Commercial boundary stabilization

Before later feature work:

- keep all local product features available independently of subscription,
- keep private signing keys, customer DB, payment systems, and anti-abuse logic outside this repo,
- version the public activation/entitlement contract,
- reject invalid/expired/device-mismatched/bundle-mismatched tokens,
- preserve offline local functionality if the commercial service is unavailable,
- test downgrade, expiry, trial, owner lifetime, and malformed token paths.

## P0.3 Migration safety foundation

Before replacing Realm:

- freeze legacy Realm fixture samples,
- record schema variants that have existed in Board-Man/Clipy lineage,
- create automated fixture import tests,
- back up legacy stores before mutation,
- verify counts, identifiers, relationships, content hashes, timestamps, pins, and templates,
- define rollback behavior before the first SQLiteData cutover build ships.

# Phase 1 — Measurement and performance budget

**Execution status: ACTIVE as of 2026-08-24; benchmark foundation committed, runtime measurement closure in progress.**

**Goal: know exactly where Board-Man is heavy before optimizing it.**

Build a repeatable benchmark harness and commit results in machine-readable form where practical.

## P1.1 Fixed benchmark fixtures

At minimum:

- empty/new profile,
- 100 history items,
- 1,000 history items,
- 10,000 history items,
- mixed text/image/file/URL payloads,
- 100 / 1,000 templates,
- high pin counts,
- long text entries,
- realistic Chromium-origin clipboard entries.

## P1.2 Measure

- cold launch to usable menu/panel,
- warm launch,
- idle RSS,
- idle CPU over a fixed 5-minute window,
- app bundle size,
- dependency/framework footprint,
- history panel open latency,
- keyboard navigation latency,
- search first-result latency,
- search full-result latency,
- paste dispatch latency, with required target-app settle measured separately from pure Board-Man dispatch overhead,
- clipboard capture-to-queryable latency from pasteboard change detection through archive + committed queryable record,
- migration duration for each fixture once a Phase 2 importer candidate exists; required for Phase 2 acceptance, not a reason to start Phase 2 early,
- SQLite file size after migration once a Phase 2 destination candidate exists; required for Phase 2 acceptance, not a Phase 1 prerequisite to implementation,
- energy impact where reproducibly measurable.

## P1.3 Initial SLO candidates

These are targets to calibrate after baseline capture, not current claims.

| Metric | Candidate target |
|---|---:|
| Idle CPU | effectively 0%, with no persistent busy polling behavior |
| History panel open, normal profile | p95 <= 80 ms |
| Search first result, 10k history | p95 <= 50 ms |
| Search query completion, 10k history | p95 <= 120 ms |
| Keyboard row-to-row interaction | no user-visible frame drop; main-thread work bounded |
| Paste dispatch overhead | p95 <= 50 ms excluding required target-app settle delay |
| Cold startup regression | <= 10% from recorded best stable baseline unless justified |
| Idle RSS regression | <= 10% from recorded best stable baseline unless justified |
| App bundle regression | gated and explained per release |

Performance CI should fail only after baselines are stable enough to avoid flaky gates.

# Phase 2 — Persistence modernization: Realm → SQLiteData

**Execution status: PASS / CLOSED as of 2026-08-25. SQLiteData is the verified cutover backend; Realm remains only inside the explicit legacy/model compatibility boundary during the rollback-support window.**

**Goal: Board-Man-owned, explicit, searchable, inspectable, migration-safe storage.**

## P2.1 Introduce `BoardManStore`

No UI/service should construct Realm or SQLite connections directly after this phase.

Define repository/store interfaces for:

- history,
- payload metadata,
- templates and folders,
- pins and timed pins,
- usage/paste counts,
- per-item labels/custom names,
- exclusions/settings that belong in structured persistence,
- migration metadata.

## P2.2 SQLiteData schema

Prefer explicit normalized tables and indexes. Candidate entities:

- `history_items`
- `history_payloads`
- `templates`
- `template_folders`
- `template_folder_membership` if required
- `pins`
- `timed_pins`
- `usage_stats`
- `applications`
- `migration_state`

Use file/blob storage for large image/file payloads when it reduces DB churn and memory pressure. Store stable references, hashes, dimensions/type metadata, and lifecycle state in SQLite.

## P2.3 Migration strategy

```text
Legacy Realm
   |
   +--> immutable backup
   |
   +--> read-only snapshot/import
   |
   v
Temporary SQLiteData DB
   |
   +--> counts verification
   +--> identifier verification
   +--> relationship verification
   +--> content/hash verification
   +--> spot payload verification
   |
   v
Atomic cutover
   |
   +--> legacy DB retained for rollback window
```

Never delete the legacy DB during the first successful migration.

## P2.4 SQLiteData acceptance gate

- [x] no normal runtime service imports RealmSwift,
- [x] no direct `Realm()` calls outside legacy importer/backend compatibility code and tests,
- [x] every currently supported legacy fixture path migrates successfully, including the schema-7 compatibility fixture and current history/template structures,
- [x] forced interruption/relaunch resumes or safely restarts migration,
- [x] corrupt manifests and same-count/wrong-digest destinations fail closed without switching the authoritative backend,
- [x] row/relationship/hash verification passes,
- [x] large-profile migration benchmark is recorded,
- [x] SQLite backup/restore smoke test passes,
- [x] app behavior tests pass using only SQLiteData.

### P2 closure evidence — 2026-08-25

- `BoardManStore` and a retained-reference `BoardManStoreRouter` own normal persistence access; normal services/controllers no longer create Realm connections directly.
- `SQLiteBoardManStore` covers history, templates/folders, relationships, ordering, usage timestamps, backup, and restore. The project pins `sqlite-data` `1.11.0` exactly.
- migration prepares an immutable legacy Realm backup, imports into a temporary SQLite candidate, verifies counts/relationships/SHA-256 digest, then performs manifest-backed cutover with resume/fail-closed behavior.
- SQLite backup/restore uses the GRDB online backup API and preserves history, folders, snippets, relationships, and private `0600` database permissions.
- focused SQLite-authoritative runtime behavior verifies create/save/rename/move/delete flows through `BoardManFolder` and `BoardManSnippet` with detached compatibility objects.
- large migration fixture: 10,000 history items + 100 folders + 1,000 snippets; verified candidate size `1,515,520` bytes. Focused migration observation was `824.13 ms`; full-suite observations varied under host load, so this is recorded as benchmark evidence rather than a hard SLO.
- closure regression: XCTest store/migration tests `21/21` PASS and Swift Testing `98/98` PASS across `16` suites; SwiftLint reported `0` serious violations.

Realm dependency removal is now permitted by the gate, but is intentionally deferred until the documented legacy rollback/compatibility window can be retired without data-loss risk.

# Phase 3 — Search and information retrieval superiority

**Goal: make finding the right clipboard item effectively instantaneous.**

## P3.1 FTS5-backed unified search

**Implementation status: PASS / CLOSED (2026-08-25).**

SQLiteData-backed unified FTS5 search now replaces the panel's prior full-array text scan. Search index synchronization covers history upsert/delete/replace, template updates/deletes/moves, and folder renames. Existing SQLite-authoritative history is backfilled on a utility queue in bounded 50-item batches; unreadable legacy payloads are marked processed rather than retried forever.

Index searchable text across:

- clipboard text,
- custom title,
- URL,
- file name/path metadata,
- source application name/bundle ID,
- templates,
- folder names,
- optional normalized metadata.

For newly captured history, local supplemental metadata records clipboard text, file paths, URLs, and source application name/bundle ID. Existing archived history can recover text/file/URL metadata from its local payload archive; historical source-application identity cannot be reconstructed because older history records never stored it.

Observed focused 10,000-item FTS queries during implementation were approximately `0.29-1.69 ms` with the latest full-regression run at `1.08 ms / 1 hit`. These are implementation observations, not a formal quiet-host p95 SLO claim.

## P3.2 Board-Man ranking

**Implementation status: PASS / CLOSED (2026-08-25).**

Ranking should combine relevance with actual workflow value, for example:

```text
text relevance
+ recency
+ usage frequency
+ pin weight
+ exact/prefix match boost
+ current-context/source-app affinity (only if local and privacy-safe)
```

Keep ranking deterministic, testable, and inspectable. Do not add opaque AI ranking to the local default path.

Implemented ranking combines exact/prefix/contains match class, pin state, usage frequency, existing display/manual order as recency/order context, and FTS relevance with deterministic tie-breaking. User-defined history display names enter the same ranker rather than being appended as a separate unordered result set.

P3 Core acceptance evidence: `BoardManStoreTests` 29/29 PASS; full regression 98/98 PASS across 16 suites; benchmark-isolated 10k panel search compatibility restored after the indexed-search transition; SwiftLint 318 warnings / 0 serious. Global lint debt remains and is not claimed closed.

## P3.3 Query capability

**Implementation status: PASS / CLOSED (2026-08-25).**

Structured query tokens are parsed into a typed `BoardManSearchRequest` and executed at the Store/SQLite boundary rather than by reintroducing full-array Swift filtering:

- `type:text|image|url|file`,
- `app:<name-or-bundle-substring>` including quoted values such as `app:"Google Chrome"`,
- `after:YYYY-MM-DD`,
- `before:YYYY-MM-DD`,
- `is:pinned`,
- `in:history|templates`.

Free-text terms and structured filters can be combined, and store-backed filters can run without a text term. Unknown or invalid tokens remain literal query text instead of being silently discarded. Pin state remains owned by the existing pin stores rather than being duplicated into SQLite. Explicit `in:` scope tokens also switch the panel into the matching History/Templates action context before results are shown, so paste/edit/delete behavior cannot operate under the wrong tab semantics.

P3.3 acceptance evidence: `BoardManSearchQueryTests` `5/5` PASS; final full regression XCTest `34/34` PASS plus Swift Testing `98/98` PASS across `16` suites; SwiftLint `320` warnings / `0` serious; final 10,000-history FTS observation `1.22 ms / 1 hit`. Fuzzy typo tolerance remains intentionally deferred because it was only a conditional candidate and is not required for Phase 3 closure while deterministic indexed search remains well within observed latency expectations.

**Phase 3 overall: PASS / CLOSED.**

# Phase 4 — Structural decomposition and dependency reduction

**Goal: make the codebase boring to navigate. Boring is excellent architecture.**

## P4.1 Break up giant coordinators

**Implementation status: CLOSED — all planned P4.1 ownership boundaries and per-category settings geometry extractions accepted (2026-08-26).**

Decompose `MenuManager` and other oversized files by behavior, not arbitrary line count.

Move ownership into focused components such as:

- panel presentation,
- history presentation,
- template presentation,
- selection/navigation,
- timestamp actions,
- paste orchestration,
- search coordination,
- demo/screenshot fixtures.

Target guideline: normal production files should generally stay below ~600 lines and focused types below ~300 lines, but cohesion is more important than mechanically hitting a number.

First accepted extraction:

- `BoardManSearchCoordinator.swift` now owns search scope/pinned eligibility, indexed lookup, benchmark fallback lookup, visible-item/hit correlation, custom history display-name compatibility, and deterministic rank application.
- `HistoryDisplayNameStore` moved out of `MenuManager.swift` into the same search boundary; `BoardManPanel` retains tab candidate selection, hide/usage filters, scope-driven tab context, UI state, and rendering.
- `MenuManager.swift` reduced from `12,774` to `12,594` lines in this slice (`-180` net) while the new focused coordinator file is `271` lines.
- direct coordinator regression verifies that custom display names remain searchable even when the SQLite FTS index has no matching payload text.
- acceptance evidence: SearchQuery focused tests `6/6` PASS; full XCTest `35/35` PASS; Swift Testing `98/98` PASS across `16` suites; SwiftLint `320` warnings / `0` serious; 10,000-item FTS observation `1.18 ms / 1 hit`.

Second accepted extraction:

- `BoardManPanelItem.swift` now owns the shared `BoardManHistoryItem`, `BoardManPanelItemSource`, and `BoardManPanelTab` presentation types that were previously buried inside `MenuManager.swift` despite being used by search, benchmarks, interaction tests, and panel rendering.
- `BoardManPanelNavigation.swift` now owns the pure horizontal navigation policy for History → Templates All → persisted template groups, including non-wrapping edge behavior and Settings no-op behavior. `BoardManPanel` now applies the returned navigation target instead of calculating the transition inline.
- `MenuManager.swift` reduced again from `12,594` to `12,518` lines in this slice (`-76` net) while the new shared model is `70` lines and the focused navigation policy is `49` lines.
- focused SearchQuery plus Entitlement/interaction verification completed with `xcodebuild` exit code `0`; the earlier direct presentation-model SearchQuery run was `6/6` PASS. SwiftLint observed `319` warnings / `0` serious in this slice.

Third accepted extraction:

- `BoardManPanelPasteCoordinator.swift` now owns panel paste-target capture/restoration, Chromium activation settling, history/snippet paste dispatch, confirmed usage-count updates, target cleanup, and paste-first timestamp shortcut sequencing.
- `MenuManager` no longer owns the previous-frontmost-app / editable-target / focus-target state or the direct history/snippet/timestamp paste handlers; panel callbacks now hide the panel and delegate the action to the coordinator.
- `MenuManager.swift` reduced from `12,518` to `12,295` lines in this slice (`-223` net), while the focused paste coordinator is `250` lines.
- paste/focus/timestamp focused verification: `24/24` PASS across `PasteCountInputServiceTests` and `BoardManInteractionRuleTests`.
- full regression after the reliability-sensitive extraction: XCTest `35/35` PASS, Swift Testing `99/99` PASS across `16` suites, SwiftLint `319` warnings / `0` serious.
- full regression retained the 10,000-item FTS benchmark at `1.21 ms / 1 hit` and the 10,000-history + 1,000-template migration benchmark passed.

Fourth accepted extraction:

- `BoardManReadmeScreenshotCoordinator.swift` now owns DEBUG-only README/demo screenshot request parsing, deterministic template fixture seeding, scene preparation, and atomic PNG capture/write behavior.
- `MenuManager` now only delegates the screenshot request with its panel reload callback; screenshot environment parsing, demo data ownership, panel scene preparation, and file export are no longer embedded in the menu/panel coordinator.
- `MenuManager.swift` reduced from `12,295` to `12,157` lines in this slice (`-138` net), while the focused screenshot coordinator is `181` lines.
- screenshot parsing moved into its own `BoardManReadmeScreenshotCoordinatorTests` suite rather than expanding the already-large interaction suite; focused screenshot + interaction verification is `12/12` PASS and the build-time SwiftLint gate returned to `0` serious violations.

Fifth accepted extraction:

- `BoardManTimestampPresentation.swift` now owns timestamp format validation/menu mapping, absolute and relative text rendering, relative number/unit/suffix/now policies, timestamp position, and bounded shortcut delay policy.
- `BoardManTimestampInteraction.swift` now owns timestamp click/long-press/mask interaction semantics plus persisted timestamp shortcut configuration; `BoardManPanelPasteCoordinator` delegates delay clamping to the timestamp presentation owner rather than duplicating that rule.
- `MenuManager.swift` reduced from `12,157` to `11,885` lines in this slice (`-272` net). The timestamp presentation owner is `269` lines and the interaction/shortcut owner is `53` lines.
- focused paste/interaction/timestamp verification is `27/27` PASS. Full regression is XCTest `35/35` PASS plus Swift Testing `103/103` across `18` suites; SwiftLint reports `319` warnings / `0` serious violations; `git diff --check` passes.

Sixth accepted extraction:

- `BoardManPanelAppearance.swift` now owns panel appearance mode, UI style, font-family resolution, theme presets, visual-effect material, and deterministic tint/row/edge/shadow color policies.
- `BoardManHistoryPresentation.swift` now owns history usage-filter labels/filter semantics, pin badge presentation, and inline image-position policy rather than leaving these display rules inside the giant coordinator.
- `MenuManager.swift` reduced from `11,885` to `11,627` lines in this slice (`-258` net). The focused owners are `204` and `56` lines respectively; their dedicated tests are `31` and `26` lines.
- focused appearance/history/interaction verification is `15/15` PASS. Full regression is XCTest `35/35` PASS plus Swift Testing `107/107` across `20` suites; SwiftLint reports `316` warnings / `0` serious violations across `82` files; `git diff --check` passes.

Seventh accepted extraction:

- `BoardManPanelHeader.swift` now owns the History/Templates header tab buttons and tab bar, including hover tracking, selection state, tab layout, accessibility labels, and selected/hover visual presentation.
- the extraction is behavior-preserving: the 182-line header implementation moved verbatim out of `MenuManager.swift`; the panel continues to instantiate and coordinate the same `BoardManHeaderTabBar` API.
- `MenuManager.swift` reduced from `11,627` to `11,445` lines in this slice (`-182` net), while the focused header owner is `183` lines.
- focused `BoardManUIRegressionTests` verification is `10/10` PASS. Full regression is `142/142` PASS (`35` XCTest + `107` Swift Testing), SwiftLint reports `316` warnings / `0` serious violations across `83` files, and `git diff --check` passes.

Eighth accepted extraction:

- `BoardManSnippetEditingPolicy.swift` now owns snippet editor-container entry eligibility, draft/title persistence, bounded folder-enable mutation, and drag-reorder identifier policy instead of leaving those rules as static helpers inside `BoardManPanel`.
- the live `saveSelectedSnippetFromPanel` path now calls the same focused persistence policy exercised by tests; this removes the previous split where `persistSnippetDraft` existed only for tests while production duplicated the save behavior inline.
- `MenuManager.swift` reduced from `11,445` to `11,393` lines in this slice (`-52` net). The focused policy owner is `63` lines.
- snippet policy tests moved out of the oversized `BoardManInteractionRuleTests` into dedicated `BoardManSnippetEditingPolicyTests.swift`; the interaction suite dropped to `328` body lines instead of suppressing the lint gate.
- focused snippet-policy + UI verification is `13/13` PASS. Full regression is `143/143` PASS (`35` XCTest + `108` Swift Testing across `21` suites); SwiftLint reports `315` warnings / `0` serious violations across `85` files; the 10,000-item FTS benchmark remained `1.40 ms / 1 hit`, the 10,000-history + 1,000-template migration benchmark passed, and `git diff --check` passes.

Ninth accepted extraction:

- `BoardManSnippetPresentation.swift` now owns snippet/template editor layout geometry, editor field/read-only state, reorder-mode labels/hints, active-group normalization, and group-summary presentation as deterministic policy rather than mixing those decisions into `BoardManPanel`.
- `MenuManager.swift` now applies those calculated states to AppKit controls while retaining UI event, dialog, and storage orchestration. Active editing still preserves unsaved field values, reorder mode remains read-only, and an empty selection preserves the historical folder-toggle behavior.
- `MenuManager.swift` reduced from `11,393` to `11,317` lines in this slice (`-76` net). The focused presentation owner is `187` lines with a dedicated `140`-line test suite.
- new snippet presentation + editing policy verification is `7/7` PASS. The first combined UI run exposed one existing sheet-visibility timing failure; the isolated `BoardManUIRegressionTests` rerun passed `10/10`, including the same filter-sheet case, and the final full regression passed `147/147` (`35` XCTest + `112` Swift Testing across `22` suites).
- SwiftLint reports `307` warnings / `0` serious violations across `87` files; the 10,000-item FTS benchmark improved in this run to `1.00 ms / 1 hit`, the 10,000-history + 1,000-template migration benchmark passed at `1280.81 ms`, and `git diff --check` passes.

Tenth accepted extraction:

- `BoardManSnippetCatalogService.swift` now owns snippet/group CRUD mutations, default/active/uncategorized folder resolution, snippet movement and post-delete ordering, plus category/snippet title normalization rather than leaving storage decisions inside the panel coordinator.
- `BoardManSnippetDialogCoordinator.swift` now owns category-name prompts, snippet/group delete confirmations, validation alerts, and the panel-aware modal/sheet presentation boundary. `MenuManager.swift` retains only user-event wiring and panel-local selection/edit state.
- the obsolete, unused `promptForSnippet` form was removed instead of being preserved as dead UI code. `MenuManager.swift` reduced from `11,317` to `11,159` lines in this slice (`-158` net); the focused catalog and dialog owners are `159` and `92` lines.
- focused catalog/editing/UI verification is `15/15` PASS. Final full regression is `149/149` PASS (`35` XCTest + `114` Swift Testing across `23` suites), with `0` failed and `0` skipped tests.
- SwiftLint reports `306` warnings / `0` serious violations across `90` files; the final 10,000-item FTS benchmark passed at `0.89 ms / 1 hit`, the 10,000-history + 1,000-template migration benchmark passed at `1020.73 ms`, and `git diff --check` passes.

Eleventh accepted extraction:

- `BoardManPanelLayoutPolicy.swift` now owns high-level panel geometry as deterministic data: header/search/settings-button frames, snippet action/category/list/editor allocation, History toolbar geometry, settings viewport/sidebar/document sizing, and compact/stacked breakpoints.
- `MenuManager.swift` now applies the calculated frames to AppKit controls instead of recomputing the same layout inline. Existing `BoardManSnippetPresentation` remains the owner of snippet-editor-internal geometry, so the new owner does not absorb unrelated responsibilities.
- `MenuManager.swift` reduced from `11,159` to `11,068` lines in this slice (`-91` net). The panel layout policy is `325` lines with a dedicated `108`-line deterministic test suite.
- focused panel-layout + UI verification is `14/14` PASS. Final full regression is `153/153` PASS (`35` XCTest + `118` Swift Testing across `24` suites), with `0` failed and `0` skipped tests.
- SwiftLint reports `307` warnings / `0` serious violations across `92` files; the final 10,000-item FTS benchmark passed at `0.45 ms / 1 hit`, the 10,000-history + 1,000-template migration benchmark passed at `848.94 ms`, and `git diff --check` passes.

Twelfth accepted extraction:

- `BoardManGeneralSettingsLayout.swift` now owns deterministic General settings and global-shortcut row geometry, including labeled rows, history-limit controls, responsive shortcut text/record/clear widths, and shortcut status placement.
- `MenuManager.swift` retains the AppKit application layer only: it supplies the actual controls and applies the calculated frames. This intentionally prioritizes a testable policy boundary over artificial line-count reduction; `MenuManager.swift` is `11,074` lines after this slice while the focused policy is `152` lines.
- dedicated `BoardManGeneralSettingsLayoutTests.swift` covers ordering, column bounds, responsive shortcut allocation, and status placement. Focused General-layout + UI verification is `12/12` PASS.
- final full regression is `155/155` PASS (`35` XCTest + `120` Swift Testing across `25` suites), with `0` failed and `0` skipped tests. SwiftLint reports `309` warnings / `0` serious violations across `94` files, and `git diff --check` passes.

Thirteenth accepted extraction:

- `BoardManSnippetSettingsLayout.swift` now owns deterministic Snippets-settings geometry: group-order controls, shortcut scroll/document sizing, per-shortcut title/detail/record/clear frames, and the Manage Snippets action placement.
- `MenuManager.swift` retains only the concrete AppKit controls and applies the layout result. The extraction removes duplicate scroll/document calculations while preserving the existing shortcut-row order and responsive width behavior.
- the focused layout owner is `116` lines with a dedicated `46`-line test suite. `MenuManager.swift` is `11,064` lines after this slice.
- focused Snippets-layout + UI verification passed before the final gate, and final full regression is `157/157` PASS (`35` XCTest + `122` Swift Testing across `26` suites), with `0` failed and `0` skipped tests.
- SwiftLint reports `309` warnings / `0` serious violations across `96` files, and `git diff --check` passes.

Fourteenth accepted extraction:

- `BoardManHistorySettingsLayout.swift` now owns deterministic History-settings geometry, including the four History behavior toggles, long-press/timestamp interaction rows, responsive timestamp-shortcut recording and delay controls, timed-pin preset/duration controls, and export/clear actions.
- `MenuManager.swift` now applies those frames to AppKit controls rather than owning the responsive calculations. The focused layout owner is `282` lines with a dedicated `52`-line test suite; the History slice reduced `MenuManager.swift` from `11,064` to `10,922` lines (`-142` net).
- focused History-layout + UI verification is `13/13` PASS.

Fifteenth accepted extraction:

- `BoardManPrivacySettingsLayout.swift` now owns deterministic Privacy, Stored Types, and hide-rule Filter geometry, including the two-column stored-type grid and responsive filter mode/text/action allocation.
- `MenuManager.swift` retains concrete controls and visibility/event wiring only. The focused privacy owner is `155` lines with a dedicated `60`-line test suite; after the History + Privacy slices `MenuManager.swift` is `10,915` lines.
- the first Privacy gate intentionally failed closed when SwiftLint flagged an 8-element helper tuple as a serious `large_tuple` violation; the helper was replaced with a focused `FilterFrames` struct before tests were accepted. Combined History + Privacy + UI focused verification is `16/16` PASS.
- final full regression is `163/163` PASS (`35` XCTest + `128` Swift Testing across `28` suites), with `0` failed and `0` skipped tests. SwiftLint reports `292` warnings / `0` serious violations across `100` files; the 10,000-item FTS benchmark passed at `1.72 ms / 1 hit`, the 10,000-history + 1,000-template migration benchmark passed at `2520.65 ms`, and `git diff --check` passes.

Sixteenth accepted extraction:

- `BoardManLicenseSettingsLayout.swift` now owns deterministic License geometry for plan/state/limits, activation-key entry, activation status, upgrade action, Pro-locked controls, and license-state notes/examples.
- Updates geometry was deliberately folded into the existing high-level `BoardManPanelLayoutPolicy` instead of creating a one-purpose file: the updates preference view now receives a deterministic centered frame from the same settings-layout owner.
- focused License + panel-layout + UI verification is `16/16` PASS before the final Appearance slice.

Seventeenth accepted extraction:

- `BoardManAppearanceSettingsLayout.swift` now owns the complete deterministic Appearance/View settings geometry: preview, layout, timestamp, usage, theme, inline-image controls, advanced relative-timestamp controls, custom color/opacity rows, and text/image preview scaling in both regular and stacked layouts.
- `MenuManager.swift` now only applies the calculated AppKit frames, manages hide/show and enabled state, updates the advanced disclosure title/icon, and refreshes the preview. Appearance geometry itself is no longer calculated inside the giant coordinator.
- the focused Appearance owner is `331` lines with a dedicated deterministic test suite. The Appearance slice reduced `MenuManager.swift` from `10,921` to `10,719` lines (`-202` net); across P4.1 the giant coordinator fell from `12,774` to `10,719` lines (`-2,055` net) while behavior moved into directly testable owners.
- final focused Appearance + License + panel-layout + UI verification is `18/18` PASS. Final full regression is `167/167` PASS (`35` XCTest + `132` Swift Testing across `30` suites), with `0` failed and `0` skipped tests.
- SwiftLint reports `266` warnings / `0` serious violations across `104` files; the final 10,000-item FTS benchmark passed at `0.53 ms / 1 hit`, the 10,000-history + 1,000-template migration benchmark passed at `887.66 ms`, and `git diff --check` passes.

**P4.1 overall: PASS / CLOSED.** General, Snippets, History, Privacy, License, Updates, Appearance/View, and high-level panel geometry are externally owned and directly testable. Search, horizontal navigation, paste/timestamp dispatch, README/demo fixture generation, timestamp formatting/interaction, panel appearance/history/header presentation, and snippet editing/presentation/catalog/dialog ownership likewise remain outside the giant coordinator.

## P4.2 Dependency audit

**Implementation status: PASS / CLOSED — dependency audit and low-value dependency removal accepted (2026-08-26).**

The audit removed external packages only where Board-Man can own a smaller, deterministic boundary without sacrificing compatibility or persistence behavior:

- **SwiftHEXColors — removed.** Its single production use was `BoardManClipData` hex-color parsing. A native parser now preserves the previous 3/4/6/8-digit formats, optional `#`, RGBA semantics, and malformed-input rejection, with dedicated compatibility tests.
- **AEXML — removed.** Its only production owner was legacy snippet XML import/export. `BoardManSnippetXMLCodec` now uses Foundation `XMLDocument` and preserves the established XML header, element ordering, whitespace, empty-element shape, entity escaping, and newline encoding. Dedicated encode/decode/round-trip tests protect the interchange format.
- **RxSwift / RxCocoa — removed.** The remaining five production consumers only needed notifications, defaults observation, frontmost-application state, and a periodic timer. They now use `NotificationCenter`, `UserDefaults.didChangeNotification`, direct `NSWorkspace.frontmostApplication`, and `DispatchSourceTimer`. The package/products were removed from the Xcode project and SwiftPM resolution, and the next build removed stale Rx bundles from the generated app/test products.

The remaining four direct package families are intentionally retained because removing them would currently reduce reliability or duplicate substantial infrastructure:

- **PINCache — retain.** It owns asynchronous memory/disk thumbnail caching used by capture, panel rendering, menu rendering, and cleanup. A plain `NSCache` replacement would lose relaunch persistence; a custom disk cache would add more code and recovery risk than it removes.
- **RealmSwift — retain as compatibility infrastructure only.** SQLiteData is the authoritative runtime store, but Realm still provides legacy migration, recovery, rollback/shadow compatibility, and legacy model decoding. Retire it only after an explicit compatibility-sunset gate proves old user data no longer needs that path.
- **Sparkle — retain.** It remains the dedicated application update infrastructure and is not duplicated by Board-Man.
- **SQLiteData — retain.** It is the authoritative persistence/search foundation established in Phase 2/3.

Acceptance evidence: SwiftHEXColors focused compatibility + clipboard verification `15/15` PASS; AEXML replacement focused XML/color/snippet verification `7/7` PASS; Rx removal focused runtime/paste/hotkey/UI verification `37/37` PASS. Final full regression is `172/172` PASS (`35` XCTest + `137` Swift Testing across `32` suites), with `0` failed and `0` skipped tests. SwiftLint reports `267` warnings / `0` serious violations across `107` files; the final 10,000-item FTS benchmark passed at `0.54 ms / 1 hit`, the 10,000-history + 1,000-template migration benchmark passed at `858.93 ms`, and the removed dependency names no longer appear in production sources, direct Xcode package/product references, or `Package.resolved`.

**P4.2 overall: PASS / CLOSED.** P4.3 concurrency and main-thread discipline is the remaining Phase 4 work.

## P4.3 Concurrency and main-thread discipline

Implementation status: **PASS / CLOSED (2026-08-26)**.

- pasteboard observation already ran on a utility queue; post-capture persistence now has its own serial utility `persistenceQueue`, keeping thumbnail/color-preview generation, PINCache writes, payload archiving, SQLite/Realm persistence, performance logging, and retention cleanup off the main thread. A debug assertion makes accidental main-thread persistence fail fast.
- clipboard capture now uses the combined `upsertClip(_:searchMetadata:)` store boundary. SQLite writes the history row plus supplemental search metadata in one `DatabaseQueue` transaction and refreshes FTS once instead of performing two transactions and two index refreshes.
- `BoardManStore` now documents the queue-safety contract explicitly: implementations own their synchronization and return detached model objects. Realm compatibility reads already open per-call Realm instances and detach returned models; SQLite synchronization remains inside its database writer.
- search remains intentionally synchronous. The final 10,000-history FTS gate is `0.82 ms / 1 hit`, so there is no long-lived asynchronous search job to supersede or cancel. `BoardManSearchCoordinator` records that async cancellation should only be introduced if profiling demonstrates a real need rather than adding actor/task machinery for decoration.
- storage/paste focused verification is `42/42` PASS. Final full regression is `172/172` PASS (`35` XCTest + `137` Swift Testing across `32` suites), including the combined SQLite metadata-write search path and the complete UI regression suite. SwiftLint reports `268` warnings / `0` serious violations across `107` files; the 10,000-history + 1,000-template migration benchmark passed at `940.92 ms`, and `git diff --check` passes.

**P4.3 overall: PASS / CLOSED. Phase 4 overall: PASS / CLOSED.** The next technical-excellence work starts at Phase 5 reliability, recovery, and privacy hardening.

# Phase 5 — Reliability, recovery, and privacy hardening

**Goal: clipboard software must be boringly trustworthy because it handles sensitive data.**

**Phase 5 status: ACTIVE. P5.2 and P5.3 are PASS / CLOSED. P5.1 automated coverage is PASS, while real-application manual acceptance remains OPEN.**

## P5.1 Paste reliability matrix

Maintain automated/manual acceptance across:

- Safari,
- Chrome/Chromium apps,
- Firefox,
- native AppKit text fields,
- Electron apps,
- terminals,
- IDEs/editors,
- rich-text destinations,
- image/file paste paths.

Test:

- normal paste,
- paste + shortcut,
- delayed/time action,
- target-switch race,
- accessibility permission loss/regrant,
- rapid repeated invocation.

**P5.1 status: AUTOMATED PASS / MANUAL OPEN.**

Automated evidence includes deterministic target-family profiles for Safari, Chromium, Firefox, Electron, terminal, and native/unknown targets; bounded activation retry/settle policy; paste-target change confirmation; clipboard text reconciliation; shortcut sequencing; paste-count deduplication; and payload/image identity coverage. The authoritative acceptance rows are maintained in `docs/boardman-paste-reliability-matrix.md`.

The current source/test checkpoint passed the Phase 5 focused suite at `40/40` and the full regression at `183/183`, with `0` failed and `0` skipped tests. These automated results do not promote any real-application row from `pending`. Phase 5 cannot close until the manual matrix is completed or explicitly re-scoped.

## P5.2 Data integrity and recovery

- DB integrity checks on suspicious failure paths,
- safe backup before migrations,
- export/import format with schema version,
- bounded recovery from malformed records,
- orphan payload garbage collection,
- thumbnail/payload rebuild when metadata permits,
- crash-safe write patterns.

**P5.2 status: PASS / CLOSED.**

Closure evidence includes SQLite `PRAGMA quick_check` and foreign-key validation; fail-closed backup and restore; a schema-versioned local Recovery Archive; payload byte-count and SHA-256 verification; duplicate-manifest, path-traversal, and destination-root rejection; restoration of history, Templates, folders, and their relationships; bounded text-payload reconstruction from recoverable metadata; thumbnail rebuild from archived image payload; exact-directory orphan `.data` collection; and atomic payload archive writes.

Verification is the current Phase 5 focused suite (`40/40` PASS) plus the current full regression (`183/183` PASS, `0` failed, `0` skipped). No release, installed-app, or manual paste claim is implied by this subphase closure.

## P5.3 Privacy

- no clipboard content sent to commercial services by default,
- explicit opt-in for any future cloud/AI content processing,
- local masking/exclusion rules applied before persistence where appropriate,
- sensitive diagnostics avoid raw clipboard contents,
- commercial-service telemetry separated from local clipboard data.

**P5.3 status: PASS / CLOSED.**

Board-Man-owned outbound request construction was audited on 2026-08-27. The only `URLSession` request surfaces are an update-feed `HEAD` check and license activation. The activation JSON contract contains only `license_key`, `device_id`, `bundle_id`, and `client_version`; no clipboard body, history title, Template content, payload bytes, or local payload path enters that request. Sparkle update checks use update-feed metadata rather than clipboard data, and no separate clipboard telemetry path exists.

Clipboard-sensitive diagnostics remain local. Home paths are redacted, line breaks are flattened, messages are capped at 1,024 characters, paste-count identity/key values are redacted, and local diagnostic files are bounded. The redaction contract is covered by the Phase 5 reliability suite and the current `183/183` full regression. Any future cloud or AI content processing remains subject to explicit opt-in and a new privacy acceptance gate.

# Phase 6 — Product capability superiority

**Goal: add capability only after the foundation is fast and clean.**

Prioritize features that strengthen the existing Board-Man workflow rather than turning it into a miscellaneous utility drawer.

Candidate areas:

1. **Search intelligence without cloud dependency**
   - richer filters,
   - query grammar,
   - local ranking,
   - duplicate/group handling.

2. **Workflow actions**
   - reusable post-paste actions,
   - chained shortcuts/actions with explicit safety boundaries,
   - per-template or per-history-item actions,
   - predictable timing presets.

3. **Pins and temporal workspace**
   - richer timed-pin rules,
   - auto-expiry visualization,
   - temporary work sets/sessions.

4. **Templates**
   - variables/placeholders if they can remain simple and local,
   - fast folder/tag retrieval,
   - keyboard-first editing.

5. **Commercial service layer**
   - cloud sync,
   - encrypted backup,
   - account services,
   - team sharing,
   - AI assistance,
   - API access.

Commercial features must not degrade startup, local search, or paste if the service is unreachable.

# Phase 7 — Release and update excellence

**Goal: every stable release should be reproducible, signed, recoverable, and easy for users to update.**

Target pipeline:

```text
version/tag
  -> clean Release build
  -> tests + performance regression checks
  -> Developer ID signing
  -> notarization
  -> stapling/verification
  -> packaged ZIP/DMG
  -> Sparkle EdDSA signature
  -> appcast.xml
  -> GitHub Release assets
  -> update acceptance from previous stable build
```

Required release checks:

- version/build consistency,
- installed app path/version/executable verification,
- codesign verification,
- `spctl` acceptance when Developer ID pipeline is active,
- notarization/staple verification,
- update feed validation,
- previous stable → new stable Sparkle upgrade test,
- rollback/recovery instructions,
- release notes generated from verified changes.

# 5. Quality score targets

These are roadmap goals, not current scores.

| Area | Target |
|---|---:|
| Code organization | 9.5 / 10 |
| Storage architecture | 9.7 / 10 |
| Migration/data safety | 9.7 / 10 |
| Search | 9.8 / 10 |
| Paste reliability | 9.7 / 10 |
| Keyboard workflow | 9.7 / 10 |
| Lightweight runtime behavior | 9.5 / 10 |
| Privacy/local-first design | 9.7 / 10 |
| Release/update system | 9.5 / 10 |
| Independent codebase | 10 / 10 |

A score is allowed to fall if measurements reveal reality. The purpose is to expose weakness, not protect a flattering number.

# 6. Definition of "lightweight"

Board-Man should not call itself lightweight merely because the UI looks small.

The term requires evidence across:

- low idle CPU,
- bounded clipboard polling cost,
- low idle RSS,
- fast cold/warm start,
- small and justified dependency graph,
- lazy image/thumbnail work,
- indexed DB queries rather than scanning everything,
- bounded cache sizes,
- no unnecessary timers/observers,
- no always-on network requirement,
- no commercial-service startup dependency.

Every optimization must preserve paste reliability and data safety.

# 7. Development execution order

Strict order unless a documented blocker requires a temporary detour:

```text
Phase 0  Current Clipy independence + license boundary close
   |
   v
Phase 1  Benchmark baseline and performance budgets
   |
   v
Phase 2  SQLiteData / BoardManStore migration
   |
   v
Phase 3  FTS5 unified search + ranking
   |
   v
Phase 4  Structural decomposition + dependency reduction
   |
   v
Phase 5  Reliability/recovery/privacy hardening
   |
   v
Phase 6  Capability expansion
   |
   v
Phase 7  Production release/update excellence
```

Some Phase 4 decomposition may be pulled slightly forward only when required to make Phase 2 safe, but it must remain scoped to the persistence boundary rather than becoming a general rewrite.

# 8. Per-phase gate template

Every phase closes only with evidence for:

1. implementation complete,
2. focused tests PASS,
3. full tests PASS,
4. Debug build PASS,
5. Release build PASS where applicable,
6. performance baseline/regression check,
7. migration/data safety checks where applicable,
8. `git diff --check` PASS,
9. installed `/Applications/Board-Man.app` updated for user-visible app changes,
10. codesign and launch verification,
11. version/build bumped when the installed product meaningfully changes,
12. branch commit with clean working tree,
13. no main push/release/deploy unless explicitly authorized.

# 9. Things this plan explicitly avoids

- full SwiftUI rewrite merely for modern appearance,
- rewriting reliable code just to remove every dependency,
- introducing cloud requirements into local clipboard operations,
- putting subscription checks around ordinary local features,
- deleting the old Realm immediately after first migration,
- optimizing without benchmarks,
- hiding Clipy-derived implementation by renaming symbols rather than replacing it,
- a giant "v1 rewrite" branch with months of untestable divergence,
- AI features before local search, persistence, paste, and recovery are excellent.

# 10. Immediate next action

**Complete P5.1 real-application paste acceptance. P5.2 and P5.3 are PASS / CLOSED; Phase 5 remains ACTIVE.**

Use `docs/boardman-paste-reliability-matrix.md` as the acceptance record. Exercise the next authorized acceptance build across the listed target families and interaction cases, classify failures before changing timing policy, and leave every unexercised row as `pending`. Automated coverage alone must not close Phase 5.

Do not reopen P5.2 or P5.3 unless fresh code, test, or runtime evidence identifies a concrete regression. Phase 1 measurement remains useful as non-blocking calibration evidence and continues to inform the remaining paste matrix and later release gates.

This document remains the default technical roadmap unless a newer explicitly approved roadmap supersedes it.
