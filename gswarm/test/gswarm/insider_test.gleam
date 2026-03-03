import gleam/option.{Some}
import gleam/list
import gleam/int
import gleam/float
import gleeunit
import gleeunit/should
import gswarm/insider
import gswarm/market
import gleamdb
import gleamdb/storage
import gleam/io

pub fn main() {
  gleeunit.main()
}

pub fn insider_detection_test() {
  // 1. Setup DB
  let assert Ok(db) = gleamdb.start_named("insider_test_db", Some(storage.ephemeral()))
  market.configure_tick_retention(db)
  
  let m_id = "gswarm-success"
  let m = market.Market(
    id: m_id, 
    question: "Gswarm?", 
    outcomes: ["Yes", "No"], 
    market_type: market.Binary, 
    status: market.Open, 
    close_time: 0, 
    source: "test"
  )
  let _ = market.create_prediction_market(db, m)
  
  // 2. Scenario: "Insider" (trader_alpha) buys at t=100. Price jumps at t=400.
  // 3. Scenario: "Retail" (trader_beta) buys at t=500. After the jump.
  
  // Probability Series: 0.5 flat until 400, then jumps to 0.7
  let base_vec = [0.5, 0.5]
  
  // Ticks
  let t1 = market.PredictionTick(m_id, "Yes", 0.5, 100, 100, "trader_alpha")
  let t2 = market.PredictionTick(m_id, "Yes", 0.5, 100, 200, "trader_gamma")
  let t3 = market.PredictionTick(m_id, "Yes", 0.5, 100, 300, "trader_gamma")
  let t4 = market.PredictionTick(m_id, "Yes", 0.7, 100, 400, "trader_delta") // The Jump
  let t5 = market.PredictionTick(m_id, "Yes", 0.7, 100, 500, "trader_beta")   // Late entry
  
  let _ = market.ingest_prediction_tick(db, t1, base_vec)
  let _ = market.ingest_prediction_tick(db, t2, base_vec)
  let _ = market.ingest_prediction_tick(db, t3, base_vec)
  let _ = market.ingest_prediction_tick(db, t4, base_vec)
  let _ = market.ingest_prediction_tick(db, t5, base_vec)
  
  // 3. Run Detection
  let scores = insider.detect_insiders(db, m_id)
  io.println("DEBUG: Detected " <> int.to_string(list.length(scores)) <> " insiders")
  list.each(scores, fn(s) {
    io.println("DEBUG: Trader " <> s.trader_id <> " | Score " <> float.to_string(s.score) <> " | Lead " <> int.to_string(s.avg_lead_time_ms))
  })
  
  // Alpha should be detected
  let alpha = list.find(scores, fn(s) { s.trader_id == "trader_alpha" })
  case alpha {
    Ok(s) -> {
       { s.score >. 0.1 } |> should.be_true()
       // Lead time should be around 300s (400 - 100)
       s.avg_lead_time_ms |> should.equal(300)
    }
    _ -> should.fail()
  }
  
  // Beta should have score 0 (bought after jump)
  let beta = list.find(scores, fn(s) { s.trader_id == "trader_beta" })
  case beta {
    Ok(s) -> s.score |> should.equal(0.0)
    _ -> Nil // Or not even in list if no trades in window found
  }
}
