# Learnings: Sovereign Intelligence (Phase 31) 🧙🏾‍♂️

## 1. The `gleam/otp/task` Gap ✅ RESOLVED
**Issue**: We initially planned to use `gleam/otp/task` for parallel execution, but discovered it was missing from our dependency version or environment.
**Solution**: We fell back to `gleam/erlang/process`, using `process.spawn` (linked) and `process.new_subject` to implement a manual concurrent scatter-gather pattern.
**Learning**: Core BEAM primitives (`spawn`, `send`, `receive`) are often more reliable and flexible than higher-level abstractions when working in a constraints-heavy environment. This "manual" approach gave us fine-grained control over process linkage and error propagation.

## 2. Pure Aggregation Reducers ✅ IMPLEMENTED
**Issue**: How to implement aggregators (`Sum`, `Avg`) that work on infinite streams without loading all data into memory?
**Solution**: We implemented aggregators as pure functional reducers in `gleamdb/algo/aggregate.gleam`.
- `Sum`: Accumulates `Int` or `Float` values, preserving type precision.
- `Avg`: Maintains a running `(Sum, Count)` tuple.
- `Median`: Requires buffering, proving that not all aggregates can be strictly streaming O(1) space.
**Learning**: Separating the *logic* of aggregation from the *execution* (engine) allows for easier testing and future extensibility (e.g., user-defined aggregates).

## 3. Parallelism Thresholds ✅ IMPLEMENTED
**Issue**: Spawning a process for every query chunk has overhead.
**Decision**: We initially hardcoded a threshold of **500 items** / **100 batch size**.
**Resolution**: Refactored into a configurable `Config` type on `DbState`. The engine now reads `db_state.config.parallel_threshold` and `db_state.config.batch_size` instead of hardcoded literals.

```gleam
import gleamdb
import gleamdb/shared/types

// Tune parallelism for your workload
gleamdb.set_config(db, types.Config(
  parallel_threshold: 1000,  // trigger parallel at 1000+ items (default: 500)
  batch_size: 200,           // chunk size per spawned process (default: 100)
))
```

**Files changed**: `types.gleam`, `engine.gleam`, `transactor.gleam`, `gleamdb.gleam`

## 4. `int.range` Versioning ✅ FIXED
**Issue**: `gleam/int`'s `range` function had a different signature than expected (reducer style vs list generator) in the installed stdlib version. `list.range` was deprecated.
**Solution**: Replaced all deprecated `list.range` calls with `int.range` reducer pattern across all test files. Key insight: `int.range` is **exclusive** on the upper bound (stop when `current == stop`), so `list.range(1, 10)` becomes `int.range(from: 1, to: 11, ...)`.

```gleam
// OLD (deprecated):
list.range(1, 10)  // -> [1, 2, ..., 10] inclusive

// NEW (int.range is exclusive on stop):
int.range(from: 1, to: 11, with: [], run: fn(acc, i) { [i, ..acc] }) |> list.reverse()
```

**Files fixed**: `time_series_test.gleam`, `performance_test.gleam`, `navigator_test.gleam`
**Learning**: Always verify standard library documentation for the *specific installed version*, as rapid ecosystem evolution can lead to API drift.
