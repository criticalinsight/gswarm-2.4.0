# Roadmap: The Sovereign Transition 🧙🏾‍♂️

GleamDB v1.3.0 was a milestone of recovery. Phases 21-23 represent **Resilient Maturity** — every critical gap from the original roadmap is now closed.

## [x] COMPLETED: The Sovereign Performance (Phase 18-20)
- **Batch Persistence**: Single I/O commit per transaction in `transactor.gleam`.
- **Silicon Saturation**: Concurrent read-concurrency via ETS indices.
- **Durable Fabric**: Mnesia substrate for BEAM-native persistence and distribution.
- **Set-based Diffing**: O(N) Reactive Datalog scaling.

## [x] COMPLETED: Resilient Maturity (Phase 21-23)

### [x] ID Sovereignty (Phase 21)
`fact.Ref(EntityId)` variant de-complects identity from data at the type level. Used across all 5 engine solver paths, Pull API, and transactor.

### [x] Raft Election Protocol (Phase 22)
Pure state machine (`raft.gleam`) with term-based voting, heartbeat liveness (50ms), randomized election timeout (150-300ms), majority quorum, automatic step-down. De-complected from replication.

### [x] NSW Vector Index (Phase 23)
`vec_index.gleam` provides O(log N) navigable small-world graph for similarity search. Transactor auto-indexes Vec values. Engine falls back to AVET scan if index is empty.

### [x] Vector Enrichment (Phase 23)
`vector.gleam` extended with `euclidean_distance`, `normalize`, `dimensions`.

### [x] Native Sharding (Phase 24)
Horizontal partitioning of facts across strictly isolated local shards (`gleamdb/sharded`). Linear scaling with logical cores on M2/M3 silicon (>10k durable writes/sec).

### [x] Deterministic Identity (Phase 25)
`fact.deterministic_uid` and `fact.phash2` ensure ID consistency across distributed nodes without coordination. Enables idempotent ingestion.

### [x] The Intelligent Engine (Phase 26)
Native **Graph Algorithms** (ShortestPath, PageRank), **Data Federation** (Virtual Predicates), and **Time Travel** (Diff API).

### [x] The Speculative Soul (Phase 27)
Frictionless "Database as a Value" with `with_facts`, recursive `pull`, and a navigational Entity API.

### [x] The Logical Navigator (Phase 28)
Cost-based query optimization and heuristic join reordering.

### [x] The Chronos Sovereign (Phase 29)
Bitemporal data model (Valid Time + System Time) and `as_of_valid` time travel.

### [x] The Completeness (Phase 30)
Atomic Transaction Functions and Composite Constraints for total integrity.

### [x] Sovereign Intelligence (Phase 31)
distributed Aggregates (`Sum`, `Count`, `Avg`, `Max`, `Min`, `Median`) and Parallel Query Execution.

### [x] Graph Algorithm Suite (Phase 32)
9 native graph predicates: `ShortestPath`, `PageRank`, etc.

### [x] HNSW Vector Indexing (Phase 44)
Hierarchical layers for true $O(\log N)$ scaling on 1M+ vector datasets. Replaced flat NSW with robust HNSW.

### [x] Advanced Join Optimization (ART) (Phase 45)
Adaptive Radix Tree integration for multi-way join optimization.

### [x] Hybrid Intelligence (Phase 3 & 4)
Integrated BM25 (keyword) and weighted vector scoring within GClaw. Tiered registry for custom inference metrics.

### [x] Adaptive Stabilization (Phase 4)
Restored durable silicon persistence (5-arity Datoms) and achieved **59x speedup** on sharded temporal query read-paths.

### [x] The Federated Pulse (Phase 15)
Multi-shard coordinate reduction for distributed aggregates and real-time WAL Streaming.

---
## [x] COMPLETED: Maintenance & Stability (v2.2.0)
- **Refactor**: Replaced deprecated `int.range` with loop-based `int.range` fold to optimize allocation.
- **Verification**: Zero-warning build and 59x verified performance gain across sharded fabric.

### [x] HTAP Foundations (Phase 55)
Columnar Attribute Chunks and Vectorized NIFs for analytical scan acceleration.

### [x] Adaptive Performance Cracking (Phase 56)
JIT cracking indices that self-refine based on predicate usage patterns.

### [x] Tiered Sovereignty (Phase 57)
Cold data spilling to disk/Mnesia with morsel-driven query load balancing.

### [x] JIT-Lite Predicate Optimization (Phase 58)
Function-closure compilation for hot virtual predicates, bypassing interpreter overhead.

### [x] Advanced Features (Phase 59)
- **Predictive Prefetching**: `query_history` ring buffer + `prefetch.analyze_history` heuristic on `Tick`.
- **Zero-Copy Serialization**: `PullRawBinary(BitArray)`, `Blob(BitArray)`, `term_to_binary` FFI bypass in `engine.pull`.

### [x] Graph Traversal DSL (Phase 60)
- **Constrained Pathfinding**: `TraversalStep(Out | In)` DSL over existing EAVT index.
- **Depth-Limited Engine**: Recursive `do_traverse` with `DepthLimitExceeded` guard.
- Inspired by SurrealDB gap analysis; delivers graph utility without complecting the data model.

## Future Directions (v2.4.0+)

| Item | Description | Priority |
| :--- | :--- | :--- |
| **Persistent Pull Cache** | LRU cache for hot pull patterns | Low |
| **Per-Hop LIMIT** | Pagination guard on graph traversal supernodes | Medium |
| **Agent Memory Context** | First-class AI context graphs (SurrealDB 3.0 parity) | High |

---

## Current Status: Phase 60 (Graph Traversal DSL) — v2.4.0
All original roadmap items through Phase 60 are complete. 125 tests passing. The system is correct, durable, speculative, parallel, horizontally scalable, graph-intelligent, temporally optimized, predictively prefetched, zero-copy serialized, and graph-traversable.

🧙🏾‍♂️: "Simple made easy. Every capability earned through the EAVT foundation, never complected."