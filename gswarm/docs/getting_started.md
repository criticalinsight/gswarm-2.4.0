# Getting Started with Gswarm 🐝

Follow these steps to initialize the sovereign fabric and run the alpha extraction engine.

## 🛠️ Prerequisites
- **Erlang/OTP 27**: Required for the Silicon Saturation (ETS) layer.
- **Gleam v1.6.3+**: Required for the Datalog engine and type safety.
- **GleamDB**: Ensure `gleamdb` is available at the relative path specified in `gleam.toml`.

## 🚀 Quick Start

1. **Clone & Setup**:
   ```bash
   git clone <gswarm-repo-url>
   cd gswarm
   gleam deps download
   ```

2. **Run the Sharded Fabric**:
   ```bash
   # Start as a Leader with 4 shards (Default)
   gleam run
   
   # Start in Lean Mode (1 Shard, M2 Pro optimized)
   gleam run -- --lean
   
   # PRIMARY ENTRY POINT: Optimized for Apple Silicon (Efficiency Cores + Logging)
   ./start_efficient.sh
   
   # Start as a Follower (Joins existing cluster)
   gleam run follower
   ```

## 🧪 What to Expect
Upon running, the alpha engine will:
1.  **Initialize**: Join the sharded fabric and boot the **Supervision Tree**.
2.  **Ingestion**: Start the `market_feed` (Manifold) and `live_ticker` (Coinbase) loops.
3.  **Insider Detection**: Logs will show "Lead-Time Lag" calculations for active traders.
4.  **Graph Intelligence**: Periodic background scans (every 5 min) will run. Look for "Intelligence Scan" headers in the logs indicating PageRank, SCC, and Aggregate statistics.
5.  **Intelligence Dashboard**: Visit `http://localhost:8085/` to see live metrics, Insider Leaderboard, and the new **Graph Intelligence** stats.
6.  **Search**: Prefix and Semantic search are available via the REPL or API.
7.  **Micro-Execution**: The `copytrader` will execute simulated $10 trades when high-confidence insiders move.

## ⚙️ Tuning Parallelism
For high-throughput workloads, tune GleamDB's parallelism settings in your startup code:
```gleam
gleamdb.set_config(db, types.Config(parallel_threshold: 200, batch_size: 50))
```

## 📖 Further Reading
- [Architecture](docs/architecture.md): Deep dive into the Rama Pattern and actor model.
- [Capabilities](docs/capabilities.md): Overview of Vector Sovereignty and Memory Safety.
