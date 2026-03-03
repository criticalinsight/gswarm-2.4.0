# Performance Sovereignty: Silicon Saturation ⚡️

GleamDB leverages Erlang Term Storage (ETS) to achieve lock-free, concurrent read performance and O(1) attribute lookups.

## The Silicon Saturation Principle

Traditional databases often bottleneck on the coordination between writers and readers. GleamDB saturates the CPU by moving core indices out of actor state and into ETS.

- **Concurrent Reads**: Multiple query processes can scan `EAVT`, `AEVT`, and `AVET` indices simultaneously without sending messages to the Transactor actor.
- **Lock-Free Lookups**: ETS `read_concurrency` ensures that readers do not block each other, even under heavy load.

## Benchmarks & Scaling

- **Read Latency**: O(1) for direct attribute lookups via Silicon Saturation (ETS).
- **Ingestion Throughput**: 
    - **Durable Mnesia**: ~2,500 events/sec (single shard).
    - **Native Sharding**: >10,000 durable events/sec (8 shards on M3 Max).
    - **SQLite WAL**: ~120,000 datoms/sec.
- **Query Optimizations**:
    - **Similarity Search**: O(log N) via HNSW graph index (vs O(N) brute-force AVET scan).
    - **Temporal Range**: **~59x speedup** for periods/since queries using native `sharded.since` implementation (Phase 4).
- **Join Performance**: Datalog joins leverage ETS `duplicate_bag` matching, providing near-native BEAM performance for complex queries.
- **Memory Efficiency**: GleamDB uses optimized tuple structures to minimize memory overhead while maintaining searchability.

## Configuration

To enable Silicon Saturation (ETS), simply start your database with a name:

```gleam
// Enables ETS indices automatically
let db = gleamdb.start_named("fast_db", storage.ephemeral())
```

When `ets_name` is present in the `DbState`, the Datalog engine (`engine.gleam`) automatically switches from `Dict` lookups to direct ETS scans.

## HNSW Vector Index

For similarity queries, GleamDB maintains a **Hierarchical Navigable Small-World (HNSW)** graph index alongside the standard EAVT/AEVT/AVET indices:

- **Auto-Indexing**: Vec values are automatically added to the HNSW graph on assertion and removed on retraction.
- **Hierarchical Search**: Probabilistic skip-list structure enables $O(\log N)$ search complexity.
- **Unit-Vector Optimization**: Normalizing vectors to unit length at ingestion allows the search engine to use pure **Dot Product** for scoring, significantly reducing CPU cycles.
- **Graph-Accelerated**: `solve_similarity` uses the HNSW graph for unbound variables, falling back to AVET scan if the index is empty.

```gleam
// Similarity search uses NSW graph automatically
let query = [Similarity(Var("market"), [0.1, 0.2, 0.3], 0.9)]
let results = gleamdb.query(db, query)
```

## Graph Algorithm Efficiency

Native algorithmic predicates are optimized for the BEAM's shared-nothing architecture:

- **Shortest Path (BFS)**: Operates in O(V + E) by leveraging the `AEVT` index for neighbors.
- **PageRank Power Method**: Uniquely optimized by pre-computing the graph structure into adjacency maps before the iterative phase. This eliminates index lookups during the heavy numeric crunching, ensuring maximum throughput.

## Federation Overhead

When using `Virtual` predicates, performance is dictated by the **Adapter Protocol**:
- **Local Resolution**: Virtual predicates are resolved in the query actor process.
- **Latency Sensitivity**: If an adapter calls a remote API, it will latency-spike that specific query branch.
- **Strategy**: Use local CSV/JSON files or in-memory caches within the adapter for real-time join performance.

## Advanced Patterns

### Parallel Querying

Since reads are lock-free, you can safely spawn multiple actors to perform parallel analytics:

```gleam
list.each(0..10, fn(_) {
  process.start(fn() {
    let results = engine.run(db, my_query, [], None)
    // Process results in parallel
  })
})
```

While reads are concurrent, writes remain serialized through the leader's Transactor. For maximum throughput, combine multiple facts into a single `transact` call to leverage batch persistence and replication.


### Parallel Query Execution (v1.9.0)

GleamDB automatically parallelizes any query branch that exceeds **500 items** in intermediate context size.

- **Mechanism**: Spawns linked `gleam/erlang/process` actors for chunks of the context.
- **Speedup**: Linear scaling for large scans or complex joins.
- **Threshold**: Hardcoded to 500 to balance spawn overhead vs parallelism gain.

## Memory Management: Fact Retention

High-frequency ingestion saturates memory quickly if history is infinite. Use **Retention Policies** to bound the growth:

```gleam
let config = fact.AttributeConfig(
  unique: False, 
  component: False, 
  retention: fact.LatestOnly
)
gleamdb.set_schema(db, "sensor/value", config)
```

Attributes with `LatestOnly` will prune their history during every transaction, ensuring O(1) memory for ephemeral streams while preserving permanent facts elsewhere.

### Parallel Recovery Velocity
When dealing with millions of historical datoms, serial recovery is a bottleneck. GleamDB's sharding implementation uses **Parallel Initialization** to saturate the CPU during boot.

- **Threshold**: Systems with >100k historical records should increase `process.receive` timeouts to 600s during startup.
- **Pattern**: Shards recover independently, then signal the leader of readiness.

### High-Frequency Tickers (The Gswarm Pattern)
In production scenarios like Gswarm (1000+ ticks/sec), combining `LatestOnly` with Mnesia's `persist_batch` is critical. This decouples the "current state" (held in lock-free ETS) from the "durability layer," allowing the system to maintain sub-millisecond responsiveness even under extreme write pressure.

### Real-Time Observability (Sovereign Console)
The Sovereign Console (Phase 8) utilizes low-overhead JSON APIs to stream actor state directly to a D3.js frontend. By calculating the topology only on-request and serving it from the existing HTTP process, the console provides high-fidelity observability without compromising the engine's core ingestion velocity.

### Distributed Aggregate coordination (Phase 15)
When querying across shards, GleamDB performs a **Coordinate Reduction** pass in the coordinator process. 
- **Efficiency**: For `SUM` and `COUNT`, individual shards return their local results, and the coordinator performs a secondary `SUM`. This avoids pulling raw data across the network.
- **Latency**: The coordination overhead is $O(S \times A)$, where $S$ is the number of shards and $A$ is the number of aggregate variables. This is significantly faster than a flat scatter-gather for large datasets.

### Reactive WAL Streaming (Phase 15)
The `subscribe_wal` API provides low-latency access to the database's write-ahead log.
- **Push vs. Pull**: By pushing datoms directly from the Transactor to subscribers, system latency for signal detection is reduced by avoiding repeated Datalog polling.
- **Impact**: Broadcasting to subscribers is a sub-millisecond operation per subscriber, as it leverages Erlang's efficient message passing.

### Predictive Prefetching (Phase 59)
GleamDB tracks recent query patterns in a `query_history` ring buffer (max 100 entries). On each `Tick` lifecycle event, `prefetch.analyze_history` identifies attributes queried ≥2 times and proactively loads them into ETS caches.

- **Enable**: Set `config.prefetch_enabled = True`.
- **Overhead**: Negligible — history logging is async via `LogQuery` message.
- **Benefit**: Eliminates cold-start latency for repeated query patterns.

### Zero-Copy Serialization (Phase 59)
When `engine.pull` encounters more datoms than `config.zero_copy_threshold`, it bypasses standard struct mapping and returns a raw `PullRawBinary(BitArray)` using Erlang's `term_to_binary/1`.

- **Configure**: Set `config.zero_copy_threshold` (default: 10,000).
- **Deserialize**: Use `ets_index.deserialize_term(bin)` to recover `dynamic.Dynamic`.
- **Benefit**: Eliminates GC pressure for large analytical payloads.

### Graph Traversal Performance (Phase 60)
The `gleamdb.traverse` API resolves multi-hop relationships using batched ETS lookups:

- **Out steps**: O(D) per entity via EAVT lookup + attribute filter.
- **In steps**: O(A) via AEVT reverse lookup.
- **Depth guard**: Expressions exceeding `max_depth` are rejected before execution.
- **Deduplication**: `list.unique()` applied per hop to prevent combinatorial explosion.

