# Board-Man Phase 1 Benchmark Methodology

Status: Phase 1 baseline harness
Created: 2026-08-24

## Purpose

This harness establishes repeatable measurements before Board-Man changes storage, search architecture, or dependency structure further. Phase 1 measurements are baselines, not claims that current performance already satisfies the candidate SLOs in the Technical Excellence Master Plan.

## Safety rules

- Do not benchmark against the user's live clipboard database as a fixed fixture.
- Deterministic panel/search/navigation fixtures run against an in-memory Realm.
- Benchmark tests validate result correctness and finite measurements, but do not fail on performance thresholds until the baseline proves stable enough for a non-flaky gate.
- User-visible runtime observations such as installed-app RSS/CPU are recorded separately from deterministic fixture benchmarks.
- Record host contention at the measurement boundary. Runs performed while unrelated builds or other processes materially load the machine may prove harness correctness, but must be marked `host-contended` and excluded from SLO calibration.
- Never terminate unrelated user processes merely to obtain a cleaner benchmark run.
- AppKit UI-regression fixtures must not depend on the XCTest host being the active application. Test panels are presented with a deterministic test-only front-ordering helper before visibility assertions.
- SQLiteData migration work remains out of scope for Phase 1.

## Deterministic fixtures

The Swift test harness covers:

- history: 0, 100, 1,000, 10,000 items,
- mixed text / URL / image / file-like metadata,
- Chromium-like URL/source metadata,
- 1,000 history items with half pinned,
- 100 long-text history entries,
- templates: 100 and 1,000 items,
- 10 template groups,
- deterministic single-hit search terms,
- vertical keyboard navigation over 10,000 history items,
- horizontal History → Templates All → group traversal.

The fixture contents are generated before measurement so fixture construction time is excluded from panel/search timings.

## Automated metrics

`BoardManPerformanceBaselineTests.phase1DeterministicPanelBaseline()` records:

- history load/filter/presentation update cost,
- 10k history synchronous search completion,
- 10k vertical keyboard row navigation,
- high-pin history load,
- long-text search,
- 100/1,000 template load,
- 1,000-template search,
- template group filtering,
- horizontal group traversal.

Each metric records iterations, p50, p95, average, and maximum milliseconds. The test prints a machine-readable JSON object prefixed with `BOARDMAN_PHASE1_BENCHMARK_JSON=` and writes the same JSON to `BOARDMAN_BENCHMARK_OUTPUT` when that variable reaches the test process, otherwise to `/tmp/boardman-phase1-benchmark.json`. The actual path is printed as `BOARDMAN_PHASE1_BENCHMARK_OUTPUT=`.

## Runtime instrumentation metrics

Runtime performance logging now separates user-visible orchestration delay from Board-Man's own measured work:

- `paste_target_restore_settle`: starts immediately before restoring the previously focused target application and ends after the target is frontmost/focused plus the required app-specific settle delay. This intentionally includes the 80 ms native-app or 240 ms Chromium settle window and is **not** compared with the paste-overhead SLO.
- `paste_dispatch_overhead`: starts only after target restoration/settling is complete, then measures Realm lookup plus pasteboard replay and synthetic paste-event enqueue through `PasteService`. This is the metric eligible for comparison with the candidate `p95 <= 50 ms` paste-dispatch-overhead SLO.
- `clipboard_capture_to_queryable`: starts when `ClipService` detects a new pasteboard `changeCount` (or explicit ingestion begins) and ends immediately after the archived payload is written and the corresponding Realm transaction commits. History trimming occurs after this marker, so the endpoint means the captured clip is queryable.

Legacy `panel_direct_paste_dispatch` / `panel_snippet_paste_dispatch` logging remains for end-to-end continuity but includes target restoration and settle behavior; it must not be used as the pure dispatch-overhead SLO metric.

## Isolated benchmark runtime profile

Set `BOARDMAN_BENCHMARK_PROFILE=1` only for explicit runtime measurement launches. The profile isolates benchmark state from the user's normal Board-Man runtime by using:

- a dedicated Application Support directory ending in `Benchmark`,
- a dedicated Realm file named `benchmark.realm`,
- a dedicated `com.uniplanck.BoardMan.Benchmark` UserDefaults suite,
- a dedicated `~/Library/Logs/Board-Man Benchmark/paste-count-input.log`,
- no legacy Realm import/recovery into the benchmark Realm,
- no launch-time accessibility permission prompt.

Normal runtime services remain active so launch/idle measurements remain representative. Do not run the normal installed Board-Man and the benchmark instance simultaneously when measuring global hotkey/input behavior; stop the normal instance, run the bounded benchmark, then relaunch the installed app.

## UI regression stability evidence

After replacing test-host activation-dependent panel presentation with the deterministic test-only helper, `BoardManUIRegressionTests` passed 90/90 executions across 10 serial iterations. The same source then passed the complete serial suite at 98/98 tests across 16 suites. After adding benchmark-only license/device-state isolation, the final source again passed the complete serial suite at 98/98 tests across 16 suites. These results validate test-harness determinism and regression safety; they are not performance SLO measurements.

## Runtime benchmark isolation acceptance

The final-source Universal Release build was launched directly with `BOARDMAN_BENCHMARK_PROFILE=1` after the installed `/Applications/Board-Man.app` instance was cleanly stopped. Production state was fingerprinted before launch, during benchmark execution, and after benchmark termination.

Expected benchmark-only artifacts were created under `~/Library/Application Support/Board-Man Benchmark`, `~/Library/Logs/Board-Man Benchmark`, and the `com.uniplanck.BoardMan.Benchmark` preferences domain, including `benchmark.realm` and Realm management files.

The following production state remained fingerprint-identical across the benchmark run:

- `~/Library/Application Support/com.uniplanck.BoardMan`
- `~/Library/Application Support/Board-Man`
- `~/Library/Application Support/Board-Man Archive`
- `~/Library/Logs/Board-Man`
- `~/Library/Preferences/com.uniplanck.BoardMan.plist`
- the exported normal `com.uniplanck.BoardMan` defaults domain

Result: runtime benchmark storage/configuration isolation **PASS**. The installed production app was relaunched successfully afterward.

This proves isolation, not performance SLO compliance. Host contention during Release dependency compilation materially distorted timing conditions, so those timing samples remain excluded from SLO calibration.

## Runtime footprint metrics

Release artifact/runtime baseline should separately record:

- app bundle size,
- executable size,
- embedded framework count/names,
- current-profile idle RSS and CPU observation,
- cold/warm launch timing when a safe isolated runtime fixture is available.

A current-profile RSS/CPU observation is not interchangeable with a fixed-fixture result and must be labeled as such. The fixed five-minute idle window is accepted only when the sampler itself completes; a runtime/stall-timeout of the sampler is not a Board-Man performance result.

## Configuration

Deterministic Swift benchmarks currently run in the Debug test host because the existing testing hooks are debug-only. Those values are useful for relative comparisons within the same harness/configuration, but must not be presented as Release SLO compliance evidence.

Release artifact size/dependency measurements are collected from the actual Release build.

A distinct search first-result metric is not claimed while Board-Man's measured test path filters synchronously to completion. Paste-dispatch instrumentation is now boundary-separated as documented above; candidate SLO calibration still requires repeated quiet-host runtime samples before becoming a gate.

Migration duration and post-migration SQLite size become measurable only after a Phase 2 migration candidate exists. They remain required future acceptance measurements, but Phase 1 does not start Phase 2 merely to manufacture those numbers.

## Invocation

Run the focused benchmark serially to avoid AppKit global-state interference:

```sh
BOARDMAN_BENCHMARK_OUTPUT=/tmp/boardman-phase1-benchmark.json \
  xcodebuild test \
  -project Board-Man.xcodeproj \
  -scheme Board-Man \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:Board-ManTests/BoardManPerformanceBaselineTests
```

The full test suite should also be executed serially while the existing shared scheme keeps `Board-ManTests` parallelizable.
