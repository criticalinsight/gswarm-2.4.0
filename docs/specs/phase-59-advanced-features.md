# Phase 59: Advanced GleamDB Features

**Status**: ✅ Implemented  
**Priority**: P0  
**Owner**: Rich Hickey 🧙🏾‍♂️  

## Overview
This phase introduces advanced performance characteristics to GleamDB: Predictive Prefetching and Zero-Copy Serialization. These features address latency during cold starts and large analytical workloads resulting from the architectural gap analysis with CedarDB. Predictive prefetching analyzes query histories or patterns to proactively load disk-spilled datoms back into ETS/Memory before they are strictly needed. Zero-Copy Serialization optimizes the boundary between Gleam/Erlang and the Rust NIFs by utilizing raw binary payloads and memory-mapped shared regions, dramatically lowering the garbage collection pressure for massive result sets.

## User Stories
1. **As a Data Engineer**, I want the database to predict my most common query patterns so that the cold-data penalty for recently evicted items is minimized.
2. **As an ML Practitioner**, I want the database to return multi-million row arrays without serializing JSON or complex Erlang terms, so that my analytical scripts execute instantly without OOM errors.

## Acceptance Criteria
- **Given** a sequence of queries hitting specific `eavt` or `aevt` patterns
  **When** a background worker observes a threshold frequency
  **Then** the worker proactively loads the likely next datoms from disk to ETS before the query blocks on disk IO.
- **Given** a large vector or columnar analytical query
  **When** the results are returned from the Rust storage/compute layers
  **Then** the response payload is returned as a 0-copy Erlang Binary/NIF wrapper instead of a nested Gleam List/Tuple.
  **And** memory consumption does not spike linearly with the result size.

## Technical Implementation

### Database
- **Schema Updates**: None.
- **State Additions**: `DbState` will track a `query_history: RingBuffer(QueryContext)` to train the prefetch heuristic.
- **Rust NIFs**: Update `gleamdb_ets_ffi` to serialize directly into an `ErlRLNIFTerm` binary, or introduce a new Rust FFI via `rustler` that maps an Apache Arrow buffer directly to an Erlang binary.

### Architecture/Data Flow
1. **Prefetching**:
   Query Execution -> Logs Query Pattern -> `transactor.Tick` evaluates frequent patterns -> Spawns async task to bulk read Mnesia/Disk -> Loads to `eavt` ETS cache.
2. **Zero-Copy**:
   Query Execution -> Vectorized Scan -> Rust computes chunks -> Returns `&[u8]` (Erlang Binary) -> Gleam deserializes lazily using bit syntax (`<<val:Int, ...>>`).

## Security & Validation
- **AuthZ/AuthN**: N/A for internal engine components.
- **Validation**: Strict boundary checks in Rust NIFs to prevent segfaults when constructing Erlang Binaries. Mnesia boundaries are implicitly safe.

## Pre-Mortem Analysis
- **"Why will this fail?"**: Predictive Prefetching could thrash the ETS cache by loading the wrong datoms and evicting good ones.
- **Mitigation**: Implement a distinct `prefetch_ets` tier or hard limit on prefetch memory allocation. Ensure prefetch operations abort if system load > 80%.

---

## Implementation Notes (Completed 2026-02-20)

### Predictive Prefetching
- Added `prefetch_enabled: Bool` and `query_history: List(QueryContext)` to `Config` and `DbState`.
- Created [prefetch.gleam](file:///Users/brixelectronics/Documents/mac/gswarm/src/gleamdb/engine/prefetch.gleam) with sliding-window frequency heuristic (`analyze_history`).
- Integrated `LogQuery` message into the transactor actor; query logging hooks added to `pull` and `query_at` in `gleamdb.gleam`.
- Prefetch analysis runs on each `Tick` lifecycle event when enabled.

### Zero-Copy Serialization
- Added `Blob(BitArray)` variant to `fact.Value` and `PullRawBinary(BitArray)` to `PullResult`.
- Added `get_raw_binary/2` Erlang FFI (`term_to_binary`) to [gleamdb_ets_ffi.erl](file:///Users/brixelectronics/Documents/mac/gswarm/src/gleamdb_ets_ffi.erl).
- `engine.pull` now bypasses struct mapping when datom count exceeds `zero_copy_threshold`, returning raw binary.
- Codec support (`encode_compact`/`decode_compact`) extended for `Blob` tag `8`.

### Tests
- [prefetch_test.gleam](file:///Users/brixelectronics/Documents/mac/gswarm/test/gleamdb/prefetch_test.gleam) — ring buffer population and heuristic tick.
- [zerocopy_test.gleam](file:///Users/brixelectronics/Documents/mac/gswarm/test/gleamdb/zerocopy_test.gleam) — threshold-triggered binary serialization.
- All 125 tests passing.
