# GleamDB 🧙🏾‍♂️

> "Simplicity is not about making things easy. It is about untangling complexity." — Rich Hickey

GleamDB is a high-performance, analytical Datalog engine built natively for the BEAM. It treats the database as an immutable value, preserves full transaction history, and leverages the BEAM's actor model for massive query concurrency.

## 🧬 Core Philosophy
1.  **The Rama Pattern**: De-complecting Storage from Query. We use Write-Optimized persistence (Log) and Read-Optimized indices (Silicon Saturation).
2.  **Immutability**: The database is a value. A transaction produces a *new* database value.
3.  **Facts, not Objects**: Data is represented as atomic facts: `(Entity, Attribute, Value, Transaction, Operation)`.
4.  **Datalog Engine**: A semi-naive deductive logic engine supports recursive queries and graph traversals.
5.  **Pluggable Persistence**: Decoupled engine logic with adapters for **Mnesia** (durability), **SQLite** (standard), and in-memory storage.

## 🚀 Key Features
- **Silicon Saturation**: Lock-free, concurrent read indices via ETS (O(1) access).
- **Time Series & Analytics**: Native `Temporal` queries, `Aggregate` functions, and `OrderBy`/`Limit` push-down predicates.
- **Vector Sovereignty**: Native similarity search via HNSW (Hierarchical Navigable Small-World) graph index — $O(\log N)$.
- **Prefix Search**: Adaptive Radix Tree (ART) index for $O(k)$ string prefix matching.
- **Raft HA**: Term-based leader election for zero-downtime failover.
- **ID Sovereignty**: `fact.Ref(EntityId)` de-complects identity. Native `phash2` support enables deterministic Entity IDs for **Idempotent Transactions**.
- **Native Sharding (v1.7.0)**: Horizontal partition of facts across logical shards (`gleamdb/sharded`) to saturate multi-core hardware. Each shard is an isolated Raft consensus group.
- **Distributed Sovereign**: Multi-node replication and transaction forwarding via BEAM distribution.
- **Graph Algorithm Suite (9 predicates)**: Native `ShortestPath`, `PageRank`, `Reachable`, `ConnectedComponents`, `Neighbors`, `CycleDetect`, `BetweennessCentrality`, `TopologicalSort`, and `StronglyConnectedComponents` — all as composable Datalog predicates.
- **Data Federation**: Query external data sources (CSV, JSON, APIs) as if they were internal facts via `Virtual` predicates.
- **Time Travel (Diff)**: Deep temporal introspection with `gleamdb.diff`.
- **Speculative Soul (Phase 27)**: Treat the database as a pure value with `gleamdb.with_facts` — non-persistent, what-if state transitions.
- **Enhanced Pull**: Selective exclusion (`pull_except`) and automated graph recursion (`pull_recursive`).
- **Logical Navigator (Phase 28)**: Cost-based query planner that automatically reorders join clauses for optimal performance.
- **Sovereign Intelligence (Phase 31)**: Next-gen analytics with **Distributed Aggregates** (`Sum`, `Avg`, `Median`) and **Parallel Query Execution** with configurable thresholds via `Config` type.
- **Temporal Isolation (Phase 2 Stabilization)**: Bidirectional temporal filtering with unified `query_at` API supporting both 'since' (lower bound) and 'as_of' (upper bound) semantics. Native integration across sharded fabric for high-performance period-over-period analytics.
- **Hybrid Retrieval (Phase 3 & 4)**: Integrated **BM25** (keyword) and **Vector** (semantic) search within a tiered architecture. Supports weighted union scoring and custom metric adapters (Importance, Sentiment).
- **Stabilization & Performance (Phase 4)**: Restored durable persistence with 5-arity `Datom` support. Demonstrated **~59x query speedup** on temporal datasets via optimized sharded read-paths.
- **The Sovereign Console (Phase 8)**: Real-time D3.js visualization of the Sovereign Fabric topology, bridging the gap between raw data and human intuition.
- **Mass Ingestion & Oracle (Phase 9)**: Scalable ingestion of 50k real-world traders with temporal news correlation.
- **Behavioral Clustering (Phase 10)**: Automated cohort discovery and color-coded visualization of trader strategies.
- **Speculative Mirroring (Phase 11)**: Anticipatory execution via Alpha-weighted trade mirroring into a dedicated "Mirror" shard (Shard 99).
- **Resilient Hardening (Phase 12)**: Automated shard failover, daily DB grooming for <1GB RAM efficiency, and API rate limiting.
- **Telegram Notification Sink**: Integrated low-latency alert system for high-confidence trading signals.
- **The Federated Pulse (Phase 15)**: Multi-shard coordinate reduction for distributed aggregates (`Sum`, `Count`, `Min`, `Max`) and real-time **WAL Streaming** for reactive push telemetry.
- **Sovereign Search (Phase 30)**: Real-time forensic verification of trader edge using **Gemini 2.5 Flash** with active **Google Search Grounding**, enforcing a strict **50% ROI Floor**.
- **OTP Native**: Queries are independent actors, allowing for introspection, suspension, and distribution.
- **GleamCMS (v2.2.0)**: A fact-oriented content management system built directly on the engine. Featuring a Lustre interactive editor, decentralized **Fact-Sync Bridge**, and the **AI Site Architect** for generating generative, section-based landing pages with WP-level flourishes.

## ⚡ Performance
> "Speed is a byproduct of correctness."

- **Concurrency**: Lock-free reads via Silicon Saturation (ETS), allowing linear scaling with CPU cores.
- **Throughput**: Capable of ingesting **~120,000 datoms/sec** (SQLite WAL) or **~2,500 events/sec** (Durable Mnesia). Sharding scales this linearly with logical cores (>10k+ durable events/sec).
- **Similarity**: $O(\log N)$ via HNSW graph index (vs O(N) brute-force scan).
- **Latency**: Sub-millisecond read access for single-entity lookups.

## 🛠️ Usage

### Installation & Initialization
Add `gleamdb` to your `gleam.toml`:
```toml
[dependencies]
gleamdb = "2.0.0"
```

Initialize with **Silicon Saturation** (ETS-backed indices) for O(1) concurrent reads:
```gleam
import gleamdb
import gleamdb/storage

// Recommended for high performance
let assert Ok(db) = gleamdb.start_named("production", Some(storage.sqlite("data.db")))
```

### Basic Transaction
```gleam
import gleamdb
import gleamdb/fact.{Uid, EntityId, Str}

let assert Ok(state) = gleamdb.transact(db, [
  #(Uid(EntityId(101)), "user/name", Str("Alice")),
  #(Uid(EntityId(101)), "user/name", Str("Alice")),
  #(Uid(EntityId(101)), "user/role", Str("Admin"))
])
```

### Native Shareded Ingestion (v1.7.0)
Saturate all cores by partitioning writes:
```gleam
import gleamdb/sharded

// Initialize cluster with 8 shards
let assert Ok(cluster) = sharded.start_link("my_cluster", 8)

// Batch ingest (automatically routed to correct shard)
let facts = [
  #(Uid(EntityId(101)), "user/name", Str("Alice")),
  #(Uid(EntityId(202)), "user/name", Str("Bob"))
]
let assert Ok(_) = sharded.batch_ingest(cluster, facts)
```

### Datalog Query
Use the fluent `q` DSL:
```gleam
import gleamdb/q
import gleam/dict

let query = q.select(["name"])
  |> q.where(q.v("e"), "user/role", q.s("Admin"))
  |> q.where(q.v("e"), "user/name", q.v("name"))
  |> q.to_clauses()

let results = gleamdb.query(db, query)
// Returns list of bindings: [#("name", Str("Alice"))]
```

### Vector Similarity Search
```gleam
import gleamdb/shared/types.{Similarity, Val, Var}

let query = [
  Similarity(Var("market"), [0.1, 0.2, 0.3], 0.9)
]
let results = gleamdb.query(db, query)
```

### Time Series & Analytics (Phase 23)
Efficiently query historical data with temporal bounds, ordering, and aggregation:

```gleam
import gleamdb/shared/types.{Temporal, OrderBy, Limit, Var, Val, Asc}

// Get the last 100 ticks for a market, ordered by time
let query = 
  q.new()
  |> q.where(Var("t"), "tick/market", Val(market_ref))
  |> q.where(Var("t"), "tick/price", Var("price"))
  |> q.where(Var("t"), "tick/timestamp", Var("ts"))
  |> q.order_by("ts", Asc)
  |> q.limit(100)
  |> q.to_clauses

### Graph, Federation & Time Travel
Native primitives for complex traversals and external data:

```gleam
// 1. Graph: Find shortest path between cities
let query = q.new()
  |> q.where(q.v("a"), "city/name", q.s("London"))
  |> q.where(q.v("b"), "city/name", q.s("Paris"))
  |> q.shortest_path(q.v("a"), q.v("b"), "route/to", "path")
  |> q.to_clauses()

// 1b. Graph: Detect trading rings
let query = q.new()
  |> q.cycle_detect("trades_with", "cycle")
  |> q.to_clauses()

// 1c. Graph: Find gatekeepers
let query = q.new()
  |> q.betweenness_centrality("link", "node", "score")
  |> q.order_by("score", Desc)
  |> q.to_clauses()

// 2. Federation: Query CSV joined with internal user data
let query = q.new()
  |> q.virtual("users_csv", [], ["name", "age"])
  |> q.where(q.v("u"), "user/name", q.v("name"))
  |> q.to_clauses()

// 3. Time Travel: What changed between tx1 and tx3?
let changes = gleamdb.diff(db, tx1, tx3)
```

### GleamCMS Fact-Sync Bridge
Decentralize your content updates by pushing atomic facts directly into the CMS store:

```bash
curl -X POST http://localhost:8000/api/facts/sync \
  -H "Authorization: Bearer sovereign-token-2026" \
  -d '[{"eid": "my-post", "attr": "cms.post/content", "val": "Updated via Fact-Sync!"}]'
```
```
```

### Memory Safety (Retention)
```gleam
let config = fact.AttributeConfig(unique: False, component: False, retention: fact.LatestOnly)
gleamdb.set_schema(db, "ticker/price", config)
```

## 📚 Documentation
- [Search & Similarity (HNSW)](docs/features/vector_index.md)
- [Prefix Search (ART)](docs/features/art.md)
- [WAL Streaming (Real-Time Pulse)](docs/features/wal_streaming.md)
- [Graph Algorithms](docs/features/graph_algorithms.md)
- [Data Federation](docs/features/federation.md)
- [Time Travel (Diff API)](docs/features/time_travel.md)
- [Performance Guide (Silicon Saturation)](docs/performance_guide.md)
- [Distributed Guide (The Sovereign Fabric)](docs/distributed_guide.md)
- [Architecture Details](docs/architecture.md)
- [Datalog Specification](docs/specs/gleam_datalog.md)
- [The Completeness (Roadmap)](docs/specs/the_completeness.md)
- [Gap Analysis](docs/gap_analysis.md)

## 🤝 Contributing
GleamDB is built with the goal of providing a "Sovereign Knowledge Service" for autonomous agents like **Sly**. Contributions that respect the de-complecting philosophy are welcome.

---
*Built with ❤️ on the BEAM*
