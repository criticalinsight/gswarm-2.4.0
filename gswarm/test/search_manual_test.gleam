import gleam/io
import gleamdb
import gswarm/market.{Market, Binary, Open}
import gleamdb/storage
import gleam/option.{Some}
import gleam/erlang/process
import gleam/list

/// Manual verification of search features.
/// Run with: `gleam run -m search_manual_test` (requires moving to src momentarily or custom runner)
/// Actually, this file is in test/ so it can be run via `gleam test` if `gleeunit` behaves.
/// But due to `gleeunit` issues with `gleamdb` distributed nodes, we keep this as reference.
pub fn main() {
  // Use start_named to avoid net_kernel conflict with other tests
  let assert Ok(db) = gleamdb.start_named("search_manual_test", Some(storage.ephemeral()))
  market.configure_tick_retention(db)
  
  // Create Markets
  let markets = [
    Market("crypto_btc", "Will BTC hit 100k?", [], Binary, Open, 0, "test"),
    Market("crypto_eth", "Will ETH flip BTC?", [], Binary, Open, 0, "test"),
    Market("sports_nba", "Will Lakers win?", [], Binary, Open, 0, "test"),
    Market("politics_us", "Who will win 2028?", [], Binary, Open, 0, "test")
  ]
  
  list.each(markets, fn(m) {
    let assert Ok(_) = market.create_prediction_market(db, m)
  })
  
  // Ingest Vectors
  let assert Ok(_) = market.ingest_prediction_tick(db, 
    market.PredictionTick("crypto_btc", "Yes", 0.5, 100, 1000, "test_trader"), 
    [1.0, 0.0]
  )
  let assert Ok(_) = market.ingest_prediction_tick(db, 
    market.PredictionTick("crypto_eth", "Yes", 0.5, 100, 1000, "test_trader"), 
    [0.9, 0.1]
  )
  let assert Ok(_) = market.ingest_prediction_tick(db, 
    market.PredictionTick("sports_nba", "Yes", 0.5, 100, 1000, "test_trader"), 
    [0.0, 0.1] // Adjusted to be orthogonal-ish to [1,0] but close to [0,1]
    // [0.0, 1.0] was used in previous test
  )
  
  // Test 1: Prefix Search (ART)
  let assert Ok(results) = market.search_markets(db, "crypto_")
  let assert 2 = list.length(results)
  let ids = list.map(results, fn(m) { m.id })
  let assert True = list.contains(ids, "crypto_btc")
  let assert True = list.contains(ids, "crypto_eth")
  
  let assert Ok(res_sports) = market.search_markets(db, "sports")
  let assert 1 = list.length(res_sports)
  
  // Test 2: Similarity Search (HNSW)
  // crypto_btc [1,0] . crypto_eth [0.9, 0.1] = 0.9
  // crypto_btc [1,0] . sports_nba [0,1] = 0.0
  let assert Ok(sim_results) = market.find_similar_markets(db, "crypto_btc", 5, 0.5)
  
  let sim_ids = list.map(sim_results, fn(m) { m.id })
  let assert True = list.contains(sim_ids, "crypto_eth")
  let assert False = list.contains(sim_ids, "sports_nba")
  
  let assert Ok(pid) = process.subject_owner(db)
  process.kill(pid)
  
  io.println("Search verification passed.")
}
