import gleam/io
import gleam/erlang/atom
import gleam/int
import gleam/list
import gleamdb/storage
import gleamdb/transactor
import gswarm/market

@external(erlang, "os", "system_time")
fn system_time(unit: atom.Atom) -> Int

fn now_micro() -> Int {
  system_time(atom.create("microsecond"))
}

pub fn main() {
  io.println("🚀 Starting Market Benchmark...")

  // 1. Setup
  let adapter = storage.ephemeral()
  let assert Ok(db) = transactor.start(adapter)
  market.configure_tick_retention(db)

  let market_id = "bench_market"
  let _ = market.create_market(db, market.Market(
    id: market_id,
    question: "Benchmark?",
    outcomes: ["YES", "NO"],
    market_type: market.Binary,
    status: market.Open,
    close_time: 0,
    source: "bench"
  ))

  // 2. Seeding Data (10,000 ticks) - BATCHED
  io.println("🌱 Seeding 10,000 ticks (batched)...")
  let start_seed = now_micro()
  
  // Create list of ticks in memory first
  let ticks_with_vecs = int.range(1, 10001, [], fn(acc, i) {
    let tick = market.PredictionTick(
      market_id: market_id,
      outcome: "YES",
      probability: 0.5,
      volume: 100,
      timestamp: i * 1000, // 1 sec intervals
      trader_id: "bench_trader"
    )
    [#(tick, [0.5, 0.5]), ..acc]
  })
  
  let _ = market.ingest_batch_with_vectors(db, ticks_with_vecs)
  
  let end_seed = now_micro()
  let diff = end_seed - start_seed
  let seed_time = diff / 1000
  io.println("✅ Seeding complete in " <> int.to_string(seed_time) <> "ms")

  // 3. Benchmark Full Scan (get_probability_series)
  let start_full = now_micro()
  let assert Ok(full_series) = market.get_probability_series(db, market_id, "YES")
  let end_full = now_micro()
  let full_duration = end_full - start_full
  io.println("Full Scan (count=" <> int.to_string(list.length(full_series)) <> "): " <> int.to_string(full_duration) <> "µs")

  // 4. Benchmark Sharded Since (get_probability_series_since) - Last 10%
  let since_ts = 9000 * 1000
  let start_opt = now_micro()
  let assert Ok(opt_series) = market.get_probability_series_since(db, market_id, "YES", since_ts)
  let end_opt = now_micro()
  let opt_duration = end_opt - start_opt
  io.println("Optimized Since (count=" <> int.to_string(list.length(opt_series)) <> "): " <> int.to_string(opt_duration) <> "µs")

  io.println("🏁 Benchmark Complete")
}
