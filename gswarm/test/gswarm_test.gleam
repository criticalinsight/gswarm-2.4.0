import gswarm/node.{type NodeContext}
import gswarm/market
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// Tests are discovered by _test suffix

pub fn smoke_test() {
  should.equal(1, 1)
}

pub fn time_series_integration_test() {
  let cluster_id = "gswarm_ts_test"
  let ctx: NodeContext = node.start(node.Leader, cluster_id) |> should.be_ok()
 
  // Configure schema (CRITICAL for Lookup to work)
  market.configure_tick_retention(ctx.db)
  
  // 1. Create a Market
  let m = market.Market("pm_test_1", "Will it rain?", ["YES", "NO"], 
    market.Binary, market.Open, 2000000000, "test")
  let assert Ok(_) = market.create_prediction_market(ctx.db, m)
  
  // 2. Ingest Ticks (out of order in time)
  let t1 = market.PredictionTick("pm_test_1", "YES", 0.4, 100, 1000, "test_trader")
  let t3 = market.PredictionTick("pm_test_1", "YES", 0.6, 100, 1002, "test_trader")
  let t2 = market.PredictionTick("pm_test_1", "YES", 0.5, 100, 1001, "test_trader")
  
  let assert Ok(_) = market.ingest_prediction_tick(ctx.db, t1, [0.4, 0.01])
  let assert Ok(_) = market.ingest_prediction_tick(ctx.db, t3, [0.6, 0.01])
  let assert Ok(_) = market.ingest_prediction_tick(ctx.db, t2, [0.5, 0.01])
  // Duplicate ingest (idempotent)
  let assert Ok(_) = market.ingest_prediction_tick(ctx.db, t2, [0.5, 0.01])
  
  // 3. Test get_probability_series (sorted by timestamp)
  let assert Ok(series) = market.get_probability_series(ctx.db, "pm_test_1", "YES")
  
  // Expect: [(1000, 0.4), (1001, 0.5), (1002, 0.6)]
  let assert [#(ts1, p1), #(ts2, p2), #(ts3, p3)] = series
  
  ts1 |> should.equal(1000)
  p1 |> should.equal(0.4)
  ts2 |> should.equal(1001)
  p2 |> should.equal(0.5)
  ts3 |> should.equal(1002)
  p3 |> should.equal(0.6)
  
  node.stop(ctx)
}

// pub fn high_concurrency_stress_test() {
//   io.println("🚀 Initiating DURABLE Baseline Benchmark (2500 events/sec)...")
//   let cluster_id = "gswarm_durable_baseline"
//   
//   // Start Durable Leader
//   let assert Ok(ctx) = node.start(node.Leader, cluster_id)
//   
//   // 5 tickers * 10 batches/sec * 50 ticks/batch = 2,500 events/sec
//   int.range(from: 1, to: 6, with: Nil, run: fn(_, i) {
//     let m_id = "durable_m_" <> int.to_string(i)
//     let m = market.Market(m_id, "Baseline?", ["Yes"],
//       market.Binary, market.Open, 0, "test")
//     let assert Ok(_) = market.create_market(ctx.db, m)
//     
//     ticker.start_high_load_ticker(ctx.db, m_id, 50, 100)
//   })
//   
//   io.println("  - Benchmark running. Monitoring for 20 seconds...")
//   process.sleep(20000)
//   
//   io.println("✅ Durable benchmark completed.")
//   node.stop(ctx)
// }

// pub fn validation_test() {
//   let cluster_id = "gswarm_test_validation"
//   let assert Ok(ctx) = node.start(node.Leader, cluster_id)
//   let tick = market.Tick("m1", "Yes", -0.5, 100, 1, "test_trader")
//   let res = market.ingest_tick(ctx.db, tick)
//   case res {
//     Error(e) -> {
//       let assert True = string.contains(e, "Negative price")
//     }
//     _ -> panic as "Validation failed"
//   }
//   node.stop(ctx)
// }

// pub fn failover_promotion_test() {
//   let cluster_id = "gswarm_test_failover"
//   let assert Ok(leader_ctx) = node.start(node.Leader, cluster_id)
//   process.sleep(200)
//   let assert Ok(follower_ctx) = fabric.join_fabric(node.Follower, cluster_id)
//   let assert Ok(leader_pid) = process.subject_owner(leader_ctx.db)
//   process.kill(leader_pid)
//   process.sleep(600)
//   let m = market.Market("promoted_m", "Works?", ["Yes"],
//     market.Binary, market.Open, 0, "test")
//   let assert Ok(_) = market.create_market(follower_ctx.db, m)
//   node.stop(follower_ctx)
// }
