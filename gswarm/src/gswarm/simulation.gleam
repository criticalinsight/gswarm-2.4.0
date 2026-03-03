import gleam/io
import gleam/int
import gleam/float
import gleam/string
import gleam/option.{None}
import gleam/erlang/process
import gleamdb
import gleamdb/fact

import gswarm/market
import gswarm/insider_store
import gswarm/ingest_batcher
import gswarm/registry_actor
import gswarm/paper_trader
import gswarm/amka_domain
import gswarm/notifier

pub fn main() {
  io.println("🧪 Starting Gswarm Runtime Simulation...")
  
  // 1. Initialize DB
  let cluster_id = "gswarm_sim_" <> int.to_string(erlang_system_time())
  let assert Ok(db) = gleamdb.start_distributed(cluster_id, None)
  
  // 2. Configure Schema (Critical for queries)
  market.configure_tick_retention(db)
  
  // DEBUG IDs
  let d_uid = fact.deterministic_uid("sim_market_1")
  let p_hash = fact.phash2("sim_market_1")
  let e_id = fact.EntityId(p_hash)
  
  io.println("DEBUG: deterministic_uid(\"sim_market_1\"): " <> string.inspect(d_uid))
  io.println("DEBUG: phash2(\"sim_market_1\"): " <> string.inspect(p_hash))
  io.println("DEBUG: EntityId(phash2): " <> string.inspect(e_id))

  // 3. Create Market
  let m_id = "sim_market_1"
  let m = market.Market(
    id: m_id, 
    question: "Will Gswarm catch bugs?", 
    outcomes: ["Yes", "No"], 
    market_type: market.Binary, 
    status: market.Open, 
    close_time: 2000000000, 
    source: "simulation"
  )
  let assert Ok(_) = market.create_prediction_market(db, m)
  io.println("✅ Market created: " <> m_id)

  // 4. Seed Data (Simulating a trend)
  io.println("🌱 Seeding 1000 ticks...")
  // Generate a sine wave trend + noise
  int.range(from: 1, to: 1001, with: Nil, run: fn(_, i) {
    let f_i = int.to_float(i)
    let price = 0.5 +. 0.3 *. float_sin(f_i /. 100.0)
    
    // Simulate Indicators
    // RSI at index 6 (0-100 range)
    let rsi = 50.0 +. 40.0 *. float_sin(f_i /. 20.0)
    // MACD at index 7 (positive/negative)
    let macd = float_sin(f_i /. 50.0)
    
    let vector = [
      price, // 0
      0.0, 0.0, 0.0, 0.0, 0.0, // 1-5
      rsi,   // 6
      macd,  // 7
      0.0, 0.0, 0.0, 0.0, 0.0 // 8-12+
    ]
    
    let tick = market.PredictionTick(m_id, "Yes", price, 100, i, "sim_trader")
    // Ingest with rich vector
    let assert Ok(_) = market.ingest_prediction_tick(db, tick, vector)
    Nil
  })
  
  io.println("⏳ Waiting for indexing...")
  process.sleep(2000)
  
  // 5. Setup Live Pipeline
  let assert Ok(store) = insider_store.start(db)
  let assert Ok(registry) = registry_actor.start(8)
  let assert Ok(batcher) = ingest_batcher.start(db, registry, store)
  
  let assert Ok(notifier_actor) = notifier.start()
  let assert Ok(trader) = paper_trader.start_paper_trader(db, m_id, 10000.0, notifier_actor)
  
  process.send(notifier_actor, notifier.RegisterStatusHandler(fn() {
    let status_sub = process.new_subject()
    process.send(trader, paper_trader.GetStatus(status_sub))
    case process.receive(status_sub, 100) {
      Ok(s) -> "💰 Balance: $" <> float.to_string(s.balance)
      Error(_) -> "⚠️ Responseless"
    }
  }))

  process.send(batcher, ingest_batcher.RegisterTrader(m_id, trader))

  // 6. Establish trader_alpha as a "Verified Insider"
  io.println("🕵️‍♂️ Establishing 'trader_alpha' as a verified insider (5 trades)...")
  int.range(from: 1, to: 5, with: Nil, run: fn(_, i) {
    let historical_trade = amka_domain.TradeActivity(
      user: "trader_alpha",
      market_title: "Will Gswarm catch bugs?",
      market_slug: m_id,
      trade_type: amka_domain.Buy,
      size: 1000.0,
      price: 0.1,
      usdc_size: 100.0,
      timestamp: -10 + i // Trade 10s before start of series
    )
    process.send(batcher, ingest_batcher.MonitorTrade(historical_trade))
    process.sleep(100)
  })
  
  io.println("⏳ Waiting for competence verification...")
  process.sleep(6000) // Wait for 5s verification window
  
  // 7. Supply current price to paper_trader
  io.println("📊 Sending current price update (t=1000)...")
  paper_trader.broadcast_tick(trader, 0.8, [0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 70.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0])
  process.sleep(100)
  
  // 8. New Trade from Insider (Should be mirrored)
  io.println("🚀 New trade from verified insider (trader_alpha)...")
  let insider_trade = amka_domain.TradeActivity(
    user: "trader_alpha",
    market_title: "Will Gswarm catch bugs?",
    market_slug: m_id,
    trade_type: amka_domain.Buy,
    size: 1000.0,
    price: 0.8,
    usdc_size: 800.0,
    timestamp: 1001
  )
  process.send(batcher, ingest_batcher.MonitorTrade(insider_trade))
  
  process.sleep(200) // 200ms latency target
  
  // 9. Trade from a "Bot" (Should be rejected as second-mover)
  io.println("🤖 Trade from a bot (follower)...")
  let bot_trade = amka_domain.TradeActivity(
    user: "bot_follower",
    market_title: "Will Gswarm catch bugs?",
    market_slug: m_id,
    trade_type: amka_domain.Buy,
    size: 50.0,
    price: 0.81,
    usdc_size: 40.0,
    timestamp: 1002 // 1s after insider
  )
  process.send(batcher, ingest_batcher.MonitorTrade(bot_trade))
  
  process.sleep(1000)
  
  // 10. Check Final Status
  io.println("📉 Verifying PaperTrader Status...")
  let status_subject = process.new_subject()
  process.send(trader, paper_trader.GetStatus(status_subject))
  let assert Ok(state) = process.receive(status_subject, 1000)
  
  io.println("💰 Final Balance: $" <> float.to_string(state.balance))
  io.println("📦 Position: " <> float.to_string(state.position) <> " units")
  io.println("📊 Total Trades: " <> int.to_string(state.trades))
  
  io.println("✨ Simulation Complete.")
}

@external(erlang, "erlang", "system_time")
fn erlang_system_time() -> Int

@external(erlang, "math", "sin")
fn float_sin(x: Float) -> Float
