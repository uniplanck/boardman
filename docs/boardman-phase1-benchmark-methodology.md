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

A distinct search first-result metric is not claimed while Board-Man's measured test path filters synchronously to completion. Likewise, existing paste-dispatch performance logging includes target-application settle behavior and cannot be compared directly with the candidate dispatch-overhead SLO until those boundaries are separated.

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
