import gleam/io
import gleam/list
import gleam/int
import gleam/float
import gleam/option.{None, Some}
import gleam/erlang/process
import gleamdb
import gleamdb/fact
import gleamdb/storage/mnesia
import gleeunit/should
import gswarm/backtest
import gswarm/strategy

pub fn main() {
  adaptive_backtest_test()
}

pub fn adaptive_backtest_test() {
  io.println("🧪 BacktestTest: Initializing...")
  
  // 1. Setup DB
  let cluster_id = "backtest_test_cluster"
  let db = case gleamdb.start_distributed(cluster_id, Some(mnesia.adapter())) {
    Ok(d) -> d
    Error(_) -> {
      let assert Ok(d) = gleamdb.connect(cluster_id)
      d
    }
  }

  // Define Schema
  let unique = fact.AttributeConfig(unique: True, component: False, retention: fact.All, cardinality: fact.Many, check: None)
  let normal = fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None)
  let _ = gleamdb.set_schema(db, "market/id", unique)
  let _ = gleamdb.set_schema(db, "tick/market", normal)
  let _ = gleamdb.set_schema(db, "tick/price/Yes", normal)
  let _ = gleamdb.set_schema(db, "tick/vector", normal)
  let _ = gleamdb.set_schema(db, "prediction/id", unique)
  let _ = gleamdb.set_schema(db, "prediction/strategy", normal)
  let _ = gleamdb.set_schema(db, "prediction/status", normal)
  let _ = gleamdb.set_schema(db, "prediction/result", normal)

  let market_id = "test_btc_usd"
  
  // Create Market Entity first
  let market_entity = fact.Uid(fact.EntityId(123456789)) // Arbitrary ID for Market
  let _ = gleamdb.transact(db, [#(market_entity, "market/id", fact.Str(market_id))])

  io.println("🌱 BacktestTest: Seeding market ticks...")
  // Pass market_entity ID to record_tick
  seed_trend_market(db, market_entity, 1, 50)
  seed_chop_market(db, market_entity, 51, 100)
  
  seed_strategy_performance(db, "trend_follower", 1, 50, "correct")
  seed_strategy_performance(db, "mean_reversion", 1, 50, "incorrect")
  
  seed_strategy_performance(db, "trend_follower", 51, 100, "incorrect")
  seed_strategy_performance(db, "mean_reversion", 51, 100, "correct")
  
  process.sleep(500) // Allow Mnesia to commit
  
  // 5. Run Fixed Backtest
  io.println("🏃 BacktestTest: Running Fixed (Trend Follower)...")
  let fixed_res = backtest.run_backtest(db, market_id, strategy.trend_follower, 10_000.0)
  
  io.println("📊 Fixed Result: " <> float.to_string(fixed_res.percent_return) <> "%")
  
  // 6. Run Adaptive Backtest
  io.println("🏃 BacktestTest: Running Adaptive...")
  let adaptive_res = backtest.run_adaptive_backtest(db, market_id, 10_000.0, 10)
  
  io.println("📊 Adaptive Result: " <> float.to_string(adaptive_res.percent_return) <> "%")
  
  // 7. Assertions
  let is_better = adaptive_res.percent_return >=. fixed_res.percent_return
  is_better |> should.be_true
}

fn range(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}

fn seed_trend_market(db: gleamdb.Db, market_ref: fact.Eid, start: Int, end: Int) {
  list.each(range(start, end), fn(i) {
    let price = 50_000.0 +. {int.to_float(i) *. 100.0}
    // Trend Follower: SMA10 (idx 0) > SMA50 (idx 2)
    let vector = [1.0, 0.0, 0.0, 0.0] 
    record_tick(db, market_ref, price, vector, i)
  })
}

fn seed_chop_market(db: gleamdb.Db, market_ref: fact.Eid, start: Int, end: Int) {
  list.each(range(start, end), fn(i) {
    let price = case i % 2 == 0 {
      True -> 55_000.0
      False -> 54_000.0
    }
    // Mean Reversion: RSI (idx 6) low
    let vector = [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 20.0] 
    record_tick(db, market_ref, price, vector, i)
  })
}

fn record_tick(db: gleamdb.Db, market_ref: fact.Eid, price: Float, vector: List(Float), ts: Int) {
  let entity = fact.Uid(fact.EntityId(ts))
  
  let facts = [
    #(entity, "tick/market", fact.Ref(match_entity_id(market_ref))),
    #(entity, "tick/price/Yes", fact.Float(price)),
    #(entity, "tick/vector", fact.Vec(vector)),
    #(entity, "tick/timestamp", fact.Int(ts))
  ]
  let _ = gleamdb.transact(db, facts)
}

fn match_entity_id(f: fact.Eid) -> fact.EntityId {
  case f {
    fact.Uid(eid) -> eid
    _ -> fact.EntityId(0) // Should not happen in test
  }
}

fn seed_strategy_performance(db: gleamdb.Db, strat: String, start_ts: Int, end_ts: Int, result: String) {
  let offset = case strat {
    "trend_follower" -> 100000
    "mean_reversion" -> 200000
    _ -> 300000
  }
  
  list.each(range(start_ts, end_ts), fn(i) {
     let entity = fact.Uid(fact.EntityId(offset + i))
     let facts = [
       #(entity, "prediction/id", fact.Str("pred_" <> strat <> "_" <> int.to_string(i))),
       #(entity, "prediction/strategy", fact.Str(strat)),
       #(entity, "prediction/status", fact.Str("verified")),
       #(entity, "prediction/result", fact.Str(result))
     ]
     let _ = gleamdb.transact(db, facts)
  })
}
