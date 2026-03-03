
# Gswarm Architecture 🧙🏾‍♂️🐝

Gswarm is designed using the **Rama Pattern** (Write-Optimized Transactional Store + Read-Optimized Indices). It leverages GleamDB's unique ability to de-complect time, logic, and context.

## 🧱 Component Topology

### 1. Sharded Transactor Nodes (`gswarm/node.gleam`)
The fabric is horizontally partitioned into **Logical Shards**. A `ShardedContext` coordinates multiple `gleamdb` instances across parallel OS processes.
- **Parallel Initialization**: Shards are spawned concurrently during startup, utilizing multi-core performance to rebuild indices in seconds.
- **Lean Mode**: The `Lean` role collapses shards for resource-efficient local simulation.

### 2. Elastic Ingestion & Insider Detection (`gswarm/ingest_batcher.gleam`)
High-throughput ingestion ingest trade activity and immediately computes **Lead-Time Lag** against price inflection points. Insiders are flagged and persisted to the `InsiderStore`.

### 3. Micro-Execution Engine (`gswarm/copytrader.gleam`)
A specialized execution actor that mirrors "Verified Insider" trades with strict slippage and capital controls ($10 max/trade). It ensures execution stability even in thin markets.

### 4. Raft Consensus & Failover (`gswarm/fabric.gleam`)
Nodes maintain cluster state via a `role_watcher_loop`. If a Leader steps down or fails, the fabric autonomously detects the new Raft leader state and performs **Autohealing**: restarting market tickers and watchers from the durable Mnesia store.

### 4. Probabilistic Intelligence (`gswarm/hll.gleam`, `gswarm/cms.gleam`)
The system maintains O(1) space approximations of:
- **Cardinality**: HyperLogLog for unique market tracking across billions of events.
- **Frequency**: Count-Min Sketch for identifying "hot" market signals in real-time.

### 5. Graph Intelligence Hub (`gswarm/graph_intel.gleam`)
A periodic analytical battery that leverages GleamDB v2.0.0 features:
- **Vector Sovereignty**: HNSW (Hierarchical Navigable Small-World) graph traversal for true $O(\log N)$ similarity search.
- **Instant Search**: ART (Adaptive Radix Tree) for $O(k)$ prefix lookups on market IDs.
- **Sovereign Intelligence**: Distributed aggregation (`q.avg`) for cross-market statistics.
- **Navigator**: Query planner visibility (`explain`) for optimizing intelligence scans.
- **Graph Suite**: Cycle detection for wash-trading, SCC for community identification, and PageRank for influence scoring.
- **Speculative Soul**: `with_facts` for "What-if" trade simulation without side effects.
- **Semantic Reflexion**: Autonomous self-correction loop powered by Gemini 2.5 Flash and Google Search grounding.

---

## 🔄 Data Flow

```mermaid
sequenceDiagram
    participant F as Manifold Feed
    participant B as Ingest Batcher
    participant I as Insider Detector
    participant GI as Graph Intel (v2)
    participant G as GleamDB (Sharded)
    participant C as Copytrader ($10)
    
    F->>B: Trade Activity / Probability Tick
    B->>I: Compute Lead-Time Lag
    I->>G: Persist Insider Fact
    
    loop Every 5 Minutes
        GI->>G: Intelligence Scan (Aggregates + Graph)
        GI->>G: Speculative Trade Simulation
        GI->>GI: Semantic Reflexion (Self-Correction)
    end

    I->>C: Trigger Micro-Copytrade (If Verified)
    C->>G: Record Execution Result
    G->>G: Compact/Prune via Pruner.gleam
```

## 🛡️ Stability & Resilience
- **Resource Awareness**: Lean mode targets the Apple Silicon M2 Pro's efficiency cores.
- **Durable WAL**: Mnesia ensures facts survive process restarts.
- **Active Paging**: `pruner.gleam` maintains a sliding window of historical state to bound RAM usage.
- **Complexity Guard**: All vector operations use $O(\log N)$ graph traversal.
- **Unit-Vector Normalization**: Mandatory normalization at the API boundary ensures `dot_product` is equivalent to `cosine_similarity`, maximizing search precision and preventing CPU hangs.
- **Configurable Parallelism**: GleamDB's `Config(parallel_threshold, batch_size)` allows tuning query concurrency per workload — critical for matching parallelism to M2 core topology.
