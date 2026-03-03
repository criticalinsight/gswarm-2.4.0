# GleamDB: Prediction Markets Learnings & Requirements

**Date**: 2026-02-13
**Source**: Gswarm Prediction Markets Implementation (Phases 34-38)
**Status**: DRAFT

## Executive Summary
Building prediction markets intelligence on GleamDB surfaced critical friction points in time-series handling, aggregation, and query expressiveness. To support financial/probability analytics natively, GleamDB requires the following enhancements.

## 1. Temporal Query Primitives
**Problem**: `get_probability_series` had to pull ALL matching facts and filter in Gleam. No "last N values ordered by timestamp" primitive.
**Requirement**:
- **TemporalRange**: Query clause `TemporalRange(attr, since, until)` returning facts ordered by transaction time.
- **Limit/Offset**: Essential for pagination and "last N" queries.

## 2. Server-Side Aggregation
**Problem**: `resolution.gleam` computed average Brier scores by querying all predictions, extracting floats, and folding manually.
**Requirement**:
- **Aggregate**: Query clause `Aggregate(attr, :avg | :sum | :count | :min | :max)`.
- **GroupBy**: Optional grouping by a secondary attribute.

## 3. Query Ergonomics (Lookup Shorthand)
**Problem**: Every ingestion function repeats `fact.Lookup(#("market/id", fact.Str(id)))` multiple times, creating noise.
**Requirement**:
- **WithEntity**: Helper to bind lookup once per transaction or query builder.
  ```gleam
  // Proposed syntax
  use entity <- gleamdb.with_entity("market/id", id)
  entity.put("tick/price", price)
  ```

## 4. Flexible Retention Policies
**Problem**: `configure_tick_retention` hard-codes each attribute name ("tick/price/Yes", "tick/probability/YES").
**Requirement**:
- **Wildcard/Prefix Support**: Ability to define retention policies for `tick/*` or regex-based patterns.

## 5. Schema Validation Constraints
**Problem**: `validate_prediction_tick` manually checks probability ∈ [0.0, 1.0] before transaction.
**Requirement**:
- **Attribute Constraints**:
  - `FloatRange(min, max)`
  - `StringEnum(values)`
  - `Regex(pattern)`

## 6. Top-K Similarity Search
**Problem**: `analyst.gleam` retrieves ALL vectors above a threshold, even if only the top 5 are needed.
**Requirement**:
- **SimilarityTopK**: Query clause `SimilarityTopK(attr, target_vector, k)` to optimize vector search.

## 7. Ordered Results
**Problem**: Query results return in arbitrary order, complicating time-series correlation.
**Requirement**:
- **OrderBy**: Query clause `OrderBy(attr, :asc | :desc)`.

## Impact Analysis
Implementing #1 (Temporal) and #6 (Top-K) would eliminate ~40% of the data-handling boilerplate in the Gswarm Analyst and Resolution modules.
## 8. Probabilistic Monitoring & Load Management
**Problem**: In high-throughput sharded environments, tracking the activity of every single market exactly is CPU/RAM intensive.
**Requirement**:
- **Bloom Filter Integration**: Native support in the query planner for shard pruning. (Phase 43).
- **Probabilistic Metrics**: Count-Min Sketch for frequency and HyperLogLog for cardinality should be first-class citizens in the Database Registry or Actor layer. (Phase 44).
- **Adaptive Batching**: The database should provide feedback on disk latency to the ingestors to adjust batch sizes dynamically.

## 9. Arity-Stability in Core APIs
**Observation**: Frequent compiler updates (like the `int.range` transition) can break core logic in sharded environments. GleamDB should prioritize stable, consistent APIs for ranges and folds to prevent build breakage during high-load phases.
