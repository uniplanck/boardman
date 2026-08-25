# Board-Man Technical Excellence Master Plan

Status: authoritative roadmap; Phase 2 PASS / CLOSED, Phase 3 PASS / CLOSED, Phase 4 ACTIVE
Created: 2026-08-21
Baseline refreshed: 2026-08-25
Execution rule: **Phase 0 is PASS / CLOSED. Phase 1 measurement remains active as non-blocking calibration work. Phase 2 persistence modernization is PASS / CLOSED. Phase 3 search and information retrieval (P3.1-P3.3) is PASS / CLOSED. Phase 4 structural decomposition and dependency reduction is ACTIVE.**

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

**Implementation status: ACTIVE — search, shared presentation model, horizontal navigation, panel paste orchestration, README/demo fixture, timestamp presentation/interaction, panel appearance, history presentation, and panel header presentation extractions accepted (2026-08-26).**

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

P4.1 remains open for the larger template and layout/presentation ownership still embedded in `MenuManager.swift`. Search, horizontal navigation, paste/timestamp dispatch, README/demo fixture generation, timestamp formatting/interaction, panel appearance, history presentation, and panel header presentation now have focused owners outside the giant coordinator.

## P4.2 Dependency audit

For each external dependency, document:

- why it exists,
- binary/runtime cost,
- maintenance/activity,
- APIs used,
- difficulty of replacement,
- whether Apple frameworks or a small Board-Man implementation are safer.

Remove dependencies with weak value. Do not replace reliable libraries with custom code solely for dependency-count vanity.

Likely high-value reviews include:

- RxSwift/RxCocoa usage versus native Observation/Combine/callbacks in the remaining surface,
- PINCache usage versus bounded native cache/storage needs,
- AEXML if legacy-only,
- SwiftHEXColors if trivial to own,
- any framework retained only because historical code once needed it.

Sparkle may remain if it is the best update solution; the objective is quality, not zero dependencies.

## P4.3 Concurrency and main-thread discipline

- isolate pasteboard polling/capture away from UI work,
- batch/coalesce DB writes,
- keep thumbnail/image decoding off the main thread,
- cancel superseded search work,
- make store access concurrency rules explicit,
- use Instruments/Time Profiler evidence before introducing actors/tasks broadly.

# Phase 5 — Reliability, recovery, and privacy hardening

**Goal: clipboard software must be boringly trustworthy because it handles sensitive data.**

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

## P5.2 Data integrity and recovery

- DB integrity checks on suspicious failure paths,
- safe backup before migrations,
- export/import format with schema version,
- bounded recovery from malformed records,
- orphan payload garbage collection,
- thumbnail/payload rebuild when metadata permits,
- crash-safe write patterns.

## P5.3 Privacy

- no clipboard content sent to commercial services by default,
- explicit opt-in for any future cloud/AI content processing,
- local masking/exclusion rules applied before persistence where appropriate,
- sensitive diagnostics avoid raw clipboard contents,
- commercial-service telemetry separated from local clipboard data.

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

**Continue Phase 4 structural decomposition. Phase 2 and Phase 3 are already PASS / CLOSED.**

P4.1 should continue by extracting coherent panel/history/template presentation responsibilities from `MenuManager.swift`, prioritizing pure layout/presentation policies and testable service boundaries over mechanical line-count reduction. Search, navigation, paste orchestration, screenshot/demo fixtures, and timestamp presentation/interaction already have focused owners. Once the remaining high-coupling presentation ownership is sufficiently separated, proceed directly to P4.2 dependency audit and then P4.3 concurrency/main-thread discipline.

Phase 1 measurement remains useful as non-blocking calibration evidence, but it no longer blocks the accepted SQLiteData migration, FTS/search work, or Phase 4 decomposition.

This document remains the default technical roadmap unless a newer explicitly approved roadmap supersedes it.
