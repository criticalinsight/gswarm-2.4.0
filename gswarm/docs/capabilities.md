# Gswarm Capabilities 🐝🛡️

## 1. High-Frequency Market Ingestion
Demonstrates the **Silicon Saturation** pillar.
- **Goal**: Ingest 10,000+ events/second.
- **Mechanism**: Sharded batching (`ingest_batcher.gleam`), parallel Mnesia writers, and **Parallel Shard Initialization** for high-velocity cluster boot.

## 2. Vector Sovereignty
Demonstrates the **Vector Similarity** pillar.
- **Goal**: Approximate Nearest Neighbor (ANN) search across millions of facts.
- **Mechanism**: `market.find_similar_markets` uses HNSW (Hierarchical Navigable Small-World) graph traversal providing $O(\log N)$ search complexity.
- **Efficiency**: Mandatory unit-vector normalization at the boundary allows $O(D)$ similarity scoring via pure `dot_product`.

## 3. Insider Intelligence
Demonstrates the **Insider Detection** pillar.
- **Goal**: Identify traders with systemic information advantage (Lead-Time Lag).
- **Mechanism**: Real-time correlation of trade timestamps against probability inflection points.

## 4. Micro-Execution Edge
- **Goal**:  Stable returns on tiny capital ($10).
- **Mechanism**: Spread-aware execution logic in `copytrader.gleam` that rejects negative-EV copies.

## 5. Adaptive Strategy Selection
- **Goal**: Hot-swap strategies based on real-time win-rates.
- **Mechanism**: `strategy_selector.gleam` identifies the best strategy for the current market regime.

## 5. Memory Safety & Active Paging
- **Goal**: Perpetual operation on restricted hardware (M2 Pro).
- **Mechanism**: `pruner.gleam` implements sliding-window history eviction.

## 6. Configurable Query Parallelism
- **Goal**: Tune concurrency to match hardware and workload.
- **Mechanism**: GleamDB's `Config(parallel_threshold, batch_size)` via `gleamdb.set_config`. Lower thresholds for tick storms, higher for analytical queries.

## 7. Graph-Theoretic Alpha Extraction
- **Goal**: Identify complex market structures (e.g., wash-trading, influence rings).
- **Mechanism**: GleamDB `Graph Suite` predicates like `cycle_detect` and `pagerank` running over "trades_with" edges.

## 8. Bitemporal Market Replay
- **Goal**: Deterministic analysis of past market regimes with historical precision.
- **Mechanism**: `Chronos` (v2.0) bitemporal queries using `as_of_valid` to separate tick ingestion time from market occurrence time.

## 9. Speculative Trade Simulation
- **Goal**: Risk-free "What-if" analysis of trade execution.
- **Mechanism**: `Speculative Soul` (`with_facts`) creates immediate, non-persistent state forks for querying hypothetical scenarios.

## 10. Invisible Query Optimization
- **Goal**: High-performance intelligence scans without manual query tuning.
- **Mechanism**: `Navigator` cost-based planner automatically optimizes join orders based on data statistics.
- **Algorithmic Guardrails**: All internal loops are complexity-aware (e.g., $O(\log N)$ search, skip historical versions during recovery) to prevent CPU hangs.

## 11. Instant Prefix Search
- **Goal**: Autocomplete-style lookup for markets and assets.
- **Mechanism**: `market.search_markets` uses the **ART (Adaptive Radix Tree)** index for $O(k)$ lookups, where $k$ is key length.
- **Efficiency**: Zero-allocation prefix scanning avoids full table scans.
## 12. Sovereign Intelligence Arc (Phases 49–53)
Demonstrates the **Autonomous Self-Correction** pillar.
- **Sentiment-Aware Context**: Ingests real-world news grounding via Google Search to calibrate market signals.
- **Distributed V-Link**: Global HNSW similarity across shards using unit-vector normalization for $O(D)$ precision.
- **Semantic Reflexion**: Uses Gemini 2.5 Flash to autonomously identify and correct logical failures in the intelligence loop.
- **Reliable Persistence**: Silicon Saturation support for ETS tables with atomic retraction and dirty-read filtering.
