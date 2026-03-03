# Gswarm 🐝 v1.3.0

> "Sovereignty is the ability to detect signal before the market moves."

Gswarm is a **Sovereign Alpha Extraction Engine** built on GleamDB. Its sole purpose is to identify "Insider" traders—those who consistently trade before probability spikes—and copytrade them with **$10 Micro-Execution** stability.

## 🚀 Pillars of the Alpha Swarm
1.  **Insider Detection**: Real-time analysis of "Lead-Time Lag" to identify traders with systemic information advantage.
2.  **Competence Verification**: Brier-calibrated scoring to distinguishing true insiders from lucky noise.
3.  **Micro-Execution ($10)**: Optimized execution logic for tiny capital, minimizing spread impact and fees.
4.  **Silicon Saturation**: High-throughput ingestion (10k+ events/sec) to catch every tick and trade.
5.  **Sharded Sovereignty**: Horizontal scaling across 12-16 logical shards on Apple Silicon.
6.  **Prediction Market Edge**: Focusing on event outcome probabilities (0.0-1.0) rather than spot prices.
7.  **Sovereign Intelligence**: Autonomous self-correction and forensic verification via **Gemini 2.5 Flash + Google Search Grounding**.
14: 8.  **The High-Alpha Floor**: Strict **50% ROI Hardness**—ensuring absolute signal purity by silencing all noise below the elite performance delta.
8.  **Scalable Recovery**: Parallel shard initialization and $O(\log N)$ vector search foundations.
9.  **The Federated Pulse (Phase 15)**: Real-time telemetry via WAL streaming and distributed aggregate coordination for global alpha detection.
10. **Configurable Parallelism**: Tunable query parallelism via GleamDB's `Config` API — adjust thresholds per workload.

## 🛠️ Implementation Details
- **`gswarm.gleam`**: Orchestrator for leader boot and cluster heartbeat.
- **`market.gleam`**: Defines `Market` and `Tick` entities (Entity-per-Tick model) with deterministic IDs.
- **`ticker.gleam`**: High-frequency data generator (Silicon Saturation).
- **`reflex.gleam`**: Datalog subscription logic (Reactive Reflexes).
- **`context.gleam`**: HNSW-accelerated vector similarity search ($O(\log N)$ Vector Sovereignty).

## ⚙️ GleamDB Configuration
Tune parallelism for high-throughput ingestion workloads:
```gleam
import gleamdb
import gleamdb/shared/types

// Lower threshold for faster parallel kickin during tick storms
gleamdb.set_config(db, types.Config(
  parallel_threshold: 200,
  batch_size: 50,
))
```

## 🔎 Search Capabilities
Gswarm includes high-performance search powered by GleamDB v2.1.0:

### Prefix Search (ART)
Instant lookups for markets/assets by ID or name using Adaptive Radix Trees.
```gleam
let assert Ok(results) = market.search_markets(db, "crypto_")
// -> Returns all markets starting with "crypto_"
```

### Semantic Search (HNSW)
Find correlation in probability space using vector embeddings.
```gleam
let assert Ok(similar) = market.find_similar_markets(db, "crypto_btc", 5, 0.8)
// -> Find top 5 markets similar to "crypto_btc" with > 0.8 cosine similarity
```

## 🧪 Running the Simulation
```bash
gleam run
```

## 🖥️ Sovereign Console (New)
Visualize the Sovereign Fabric in real-time:
1.  Start Gswarm: `gleam run`
2.  Open **[http://localhost:8085/console](http://localhost:8085/console)**
3.  Observe the Force-Directed Graph of Active Shards, Markets, and Traders.

## 🤖 Telegram Bot (New)
The system now broadcasts high-alpha signals to Telegram.
- **Commands**:
    - `/leaderboard`: View the top "Insider" traders.
    - `/status`: Check system health and wallet balance.
- **Configuration**: Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in `.env`.

## 🆕 Recent Updates (v1.3.0)
- **Intelligence Arc**: Completed Phases 49–53:
    - **Sentiment-Aware Context**: Integration of news grounding and heuristic sentiment facts.
    - **Distributed V-Link**: $O(\log N)$ HNSW search foundations for global similarity.
    - **Self-Correction Loop**: Autonomous signal gating and calibration.
    - **Semantic Reflexion**: Self-healing intelligence via Gemini 2.5 Flash.
- **Reliability Upgrade**: Fixed critical Silicon Saturation bugs in `gleamdb` (vendored):
    - **Atomic Retraction**: Fixed ETS-mode `RetractEntity` logic.
    - **Correct Reads**: Implemented active datom filtering for `get` operations on ETS tables.
- **Performance**: Standardized on unit-vector normalization for zero-cost cosine similarity.

---
*Built as a reference implementation for GleamDB 🧙🏾‍♂️*
