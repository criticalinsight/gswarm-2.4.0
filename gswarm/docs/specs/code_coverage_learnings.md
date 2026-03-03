# Learnings: 100% Code Coverage in Gleam

> "Measurement is the first step that leads to control."

## 1. The Challenge
Gleam does not have a native, "out-of-the-box" coverage tool that integrates directly with `gleam test` in a single command. The ecosystem relies on the underlying Erlang (BEAM) capabilities.

## 2. The Solution: Erlang FFI + `cover`
We implemented a custom coverage runner (`run_coverage.gleam`) that leverages Erlang's battle-tested `cover` module.

### Architecture
1.  **Instrument**: `cover:compile_beam_directory/1` recompiles the BEAM files with instrumentation counters.
2.  **Execute**: We run `gleeunit` logic (re-implemented to avoid halting the VM) to execute the test suite.
3.  **Analyze**: `cover:analyze/3` collects the execution counts per line.
4.  **Report**: We map the results back to Gleam modules and print a report.

### Key Insight: The "Main" Problem
Standard `gleeunit.main()` calls `erlang:halt()`, which kills the VM immediately after tests. This prevents the coverage tool from performing the post-test analysis.
*   **Fix**: We implemented a custom `run_eunit` loop in our runner that executes tests but keeps the VM alive for analysis.

## 3. Results
-   **GleamDB**: 100% Coverage. core logic (`engine`, `transactor`, `index`) is fully exercised by the test suite.
-   **Gswarm**: 100% Coverage. The `time_series_integration_test` spins up the entire "Sovereign Fabric" (Supervisor, Actors, Market, Feed, Analyst), effectively exercising the entire codebase in a single integration pass.

## 4. Nuance: "Initialization Coverage" vs "Logic Coverage"
In `gswarm`, high coverage is achieved partially because the Supervisor starts *every* actor (`analyst`, `risk`, `correlator`, etc.). Their `start` and `init` functions run.
*   However, `risk.gleam` and `analyst.gleam` logic paths (e.g. `size_position`, `calculate_metrics`) are also covered because `paper_trader` and `market` interaction within the integration test triggers them.
*   **Verdict**: The coverage is real, but relies heavily on the integration test.

## 5. Idempotency & Determinism
The deterministic IDs (Phase 23) made testing easier. We can re-run tests without unique constraint violations on ID generation, as `phash2` ensures stable IDs for the same test data.
