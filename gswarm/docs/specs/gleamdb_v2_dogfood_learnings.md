# Learnings: GleamDB v2.0.0 Dogfooding in Gswarm

**Mission Status**: ✅ MISSION ACCOMPLISHED (Surgical Verification Complete)
**Dogfooding Context**: Sharded Gswarm Fabric (Lean Mode - 1 Shard)
**Features Exercised**: Phases 27, 28, 29, 30, 31, 32

---

## Executive Summary
GleamDB v2.0.0 has been successfully integrated into Gswarm and verified under live execution. All 6 major features added since v1.7.1 were exercised via the `graph_intel.gleam` module. After initial friction regarding attribute naming and ingestion timing, robust debug instrumentation proved that the engine correctly persists facts, calculates aggregates, and detects graph cycles in a sharded environment.

## Feature-by-Feature Learnings

### 1. Speculative Soul (`with_facts`)
- **Score**: 8/10
- **Learnings**: Extremely powerful for "What-if" market simulations. 
- **Friction**: The biggest DX trap is that `with_facts` returns a `DbState` (pure value), but `gleamdb.query` ONLY accepts `Db` (the actor handle). 
- **Verification**: Fixed in `graph_intel.simulate_trade` by using `engine.run` directly on the speculative state.

### 2. Navigator (Cost-Based Planner)
- **Score**: 10/10
- **Learnings**: An "invisible" win. `explain` confirms the planner automatically prioritized selectively small datasets (`insider/confidence`). Zero code changes required for massive efficiency gains.

### 3. Chronos (`as_of_valid`)
- **Score**: 9/10 (Improved)
- **Learnings**: `transact_at` allows backfilling historical data with correct valid-time semantics.
- **Verification**: The v2.0.0 refactor introduced `QueryMetadata`, making temporal debugging significantly easier by returning the effective `tx_id` and `valid_time` with every result.

### 4. Completeness (`register_composite`)
- **Score**: 6/10
- **Learnings**: Essential for preventing duplicate ticks.
- **Friction**: Ephemeral by design. Unlike rules, composites are not persisted and must be re-registered on node restart (verified in `gswarm.main`).

### 5. Sovereign Intelligence (Aggregates)
- **Score**: 9/10
- **Learnings**: `q.avg` and `q.count` provide high-level insights for paper trading stats with push-down performance.
- **Verification**: Successfully aggregated 130+ live probability ticks.
- **Note**: "Attribute Mismatch Silent Failure" — Ensure standardized attributes (like `tick/probability`) are used.

### 6. Graph Algorithmic Suite
- **Score**: 9.5/10
- **Learnings**: `CycleDetect` and `StronglyConnectedComponents` are game-changers for insider detection.
- **Verification**: `detect_wash_trades` successfully identified a seeded cyclic trading ring (A->B->C->A).
- **Friction**: Strictly requires `Ref(EntityId)` for edges. Providing string IDs leads to silent empty results.

---

## Summary Table

| Phase | Feature | DX Score | Integration Effort | Gswarm Value |
|-------|---------|----------|-------------------|--------------|
| 27 | Speculative Soul | 8/10 | Medium | High |
| 28 | Navigator | 10/10 | Zero | Medium |
| 29 | Chronos | 8/10 | Low | High |
| 30 | Completeness | 6/10 | Medium | High |
| 31 | Aggregates | 9/10 | Low | High |
| 32 | Graph Suite | 9.5/10 | Low | Ultra |

---

## Deep Architectural Insights

### 7. Sovereign Synchronization (The "Visibility Gap")
During live dogfooding, we observed "Empty Results" for aggregates even when facts were being ingested at 130+ per second.
- **Cause**: In a sharded context, facts transacted to Shard 0 are not immediately visible to Shard-local analytical loops if there is an actor-mailbox backlog.
- **Naming Conflict**: We also identified a critical global name conflict where multiple sharded clusters were competing for the singleton `gleamdb_leader`.
- **Resolution**: v2.0.0 now uses cluster-specific namespace for leaders (`gleamdb_leader_NAME`), allowing parallel isolated sharded environments (ideal for multi-tenant swarms).
- **Learning**: Distributed systems require a "Settling Time" (we added a 10s grace period) or an explicit "Sync" primitive before running analytical batteries.

### 8. Silicon Saturation (M2 Pro Performance)
GleamDB’s `Config(parallel_threshold, batch_size)` is critical for the M2.
- **Observation**: Over-parallelizing small query sets (e.g., <500 datoms) increases overhead due to Gleam/OTP process spawning.
- **Tuning**: In Gswarm, setting `parallel_threshold: 200` proved optimal for keeping the M2's efficiency cores saturated without drowning the performance cores in coordination.

### 9. The Metadata Mystery ✅ RESOLVED
`as_of_valid(T)` returns a standard `List(Dict)`.
- **Resolution**: Refactored `QueryResult` into a record:
  ```gleam
  pub type QueryResult {
    QueryResult(
      rows: List(Dict(String, Value)),
      metadata: QueryMetadata
    )
  }
  ```
- **Benefit**: Every query now carries its provenance (`tx_id`, `valid_time`, `execution_time_ms`, and `shard_id`).

### 10. Graph Locality Constraints
GleamDB v2.0 graph predicates (SCC, PageRank) are **Locality-Aware**.
- **Observation**: They operate on the shard-local state.
- **Mitigation**: Gswarm uses a deterministic `shard_key(market_id)` for the `trades_with` edges to ensure that trading clusters stay localized on a single shard, making cycle detection possible without cross-shard joins.

### 11. The DSL vs. Ergonomics Balance
Constructing aggregates like `q.avg` requires nesting a `QueryBuilder` inside another.
- **Friction**: This leads to verbose `List(BodyClause)` nesting.
- **Insight**: A more fluent `q.where(...).avg(...)` would significantly improve the DX for analytical pipelines.

### 12. The Vector Performance Crisis (O(N²) Fix) ✅ RESOLVED
During sharded initialization, we hit a 100% CPU hang as the historical dataset grew.
- **Discovery**: Insertion was O(N), leading to O(N²) bulk loading. Redundant magnitude calculations also added massive overhead.
- **Fix**: Implemented **HNSW (Hierarchical Navigable Small-World)** greedy search ($O(\log N)$) and **Unit-Vector Normalization**. 
- **Learning**: Performance is part of the "Sovereign" contract. Algorithmic complexity must be audited for every EAVT loop.

## Strategic Recommendations
1. **Unify `Db` / `DbState` Querying**: The public API needs a unified way to query both actor handles and pure state values.
2. **Persistent Constraints**: `register_composite` should be durable.
3. **Graph Type Safety**: `engine` should log warnings if graph predicates hit non-Ref attributes.
4. **Metadata Maturity**: Standardize the use of `QueryResult.metadata.shard_id` in sharded query aggregators to identify bottleneck shards.

---
*Generated from dogfood session: 2026-02-15*
