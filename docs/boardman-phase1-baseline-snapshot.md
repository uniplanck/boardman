# Board-Man Phase 1 Baseline Snapshot

Captured: 2026-08-24
Status: Phase 1 baseline foundation GREEN; stable SLO calibration pending quiet-host measurements

## Repository

- Branch: `refactor/boardman-independent-core-20260821`
- HEAD at Phase 1 entry: `6f7fbfcd066b3e21830adcaa1400038c39cf9896`
- `origin/main`: `78c86fd8da103bb9ece87259c02e608bba49a894`
- Divergence at entry: 3 commits ahead / 0 behind
- Working tree at entry: clean

## Independent-core state at Phase 1 entry

- Swift source/test files: 61
- CPY-named Swift files: 0
- Clipy-organization package references in `Package.resolved`: 0
- RealmSwift imports in production Swift files: 13 files
- Direct `Realm()` construction sites in production Swift files: 59

The remaining Realm counts are Phase 2 inputs, not Phase 1 migration work.

## Release artifact footprint

Measured from the verified Release build in Xcode DerivedData at Phase 1 entry:

- `Board-Man.app`: 36,088 KiB by `du -sk` (about 35.2 MiB)
- main executable: 31,804,640 bytes
- directly embedded top-level frameworks in `Contents/Frameworks`: 1
- embedded framework: `Sparkle.framework`

Swift Package pins still include AEXML, PINCache, PINOperation, Realm Core/Swift, RxSwift, Sparkle, SwiftHEXColors, and the SwiftLint plugin. Package presence does not imply each package contributes equally to the final runtime bundle; dependency-cost attribution remains a later Phase 1/Phase 4 measurement task.

## Provisional measurement observations

The deterministic harness now executes successfully and writes machine-readable JSON. The latest captured timing run is intentionally **excluded from SLO calibration** because the host was heavily contended. At the measurement boundary, unrelated Brave/The-Agents processes and other build activity drove system load averages as high as `35.29 / 27.52 / 19.16`. Raw values and exclusion metadata are preserved in `docs/boardman-phase1-baseline-20260824.json` rather than discarded.

Current installed-profile observations from 2026-08-24 are also provisional:

- panel visible fast: 13 samples, p50 61.0 ms, p95 83.7 ms,
- history reload: 12 samples, p50 80.1 ms, p95 177.7 ms,
- panel prewarm: 5 samples, p50 578.4 ms, p95 825.1 ms,
- direct paste dispatch: 1 sample, 333.0 ms; this timing includes target-app settle behavior and is not directly comparable with the <=50 ms overhead candidate,
- installed Release process point observation: PID 2108, RSS 75,456 KiB, CPU 0.0% after about 1h25m runtime.

A five-minute idle sampler was attempted but was terminated by the GAF sampler stall timeout before an aggregate result was produced. That run is invalid and is not a Board-Man failure or accepted performance measurement.

## Measurement interpretation

- Deterministic panel/search/navigation benchmark values are recorded by the Debug test host and should be compared only against the same harness/configuration until a Release-isolated fixture runner exists.
- Timing runs performed under material unrelated host load are labeled `host-contended` and excluded from SLO calibration.
- Release artifact footprint values come from the actual Release build.
- Current-profile process RSS/CPU observations are observational and are not substitutes for fixed-fixture measurements.
- Search first-result latency is not separately claimed while the measured path filters synchronously to completion.
- Migration duration and SQLite file size remain pending until a Phase 2 migration candidate exists; Phase 2 has not started.
- Candidate SLOs in the master plan remain targets, not pass/fail claims, until repeated quiet-host baseline runs establish variance.

## Remaining Phase 1 measurements

- repeat deterministic fixture measurements under a quiet-host condition and establish variance,
- complete a valid fixed five-minute idle CPU/RSS window,
- create a verified isolated profile for cold/warm launch measurement,
- separate paste-dispatch overhead from required target-app settle delay,
- add clipboard capture-to-queryable latency instrumentation,
- only then calibrate non-flaky performance gates.
