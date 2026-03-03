// graph_intel.gleam — Dogfood GleamDB v2.0.0 (Phases 27-32) in Gswarm
//
// This module exercises EVERY major feature added since v1.7.1:
//  - Phase 27: Speculative Soul  (`with_facts` for what-if simulation)
//  - Phase 28: Navigator         (cost-based planner — automatic, tested via `explain`)
//  - Phase 29: Chronos           (`transact_at`, `as_of_valid` for bitemporal replay)
//  - Phase 30: Completeness      (`register_composite` for market data integrity)
//  - Phase 31: Intelligence      (`q.avg`, `q.sum`, `q.count` for distributed aggregates)
//  - Phase 32: Graph Suite       (9 graph predicates for insider/market network analysis)

import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/dict
import gleam/result
import gleam/option.{None}
import gleam/erlang/process
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/q
import gleamdb/engine

import gswarm/market
import gswarm/node.{type ShardedContext}


// ─────────────────────────────────────────────────────────────────
// Phase 30: Composite Constraints — enforce market data integrity
// ─────────────────────────────────────────────────────────────────

/// Register composite uniqueness constraints on the primary shard.
/// Prevents duplicate (market_id, timestamp) tuples from entering the DB.
pub fn register_market_constraints(ctx: ShardedContext) -> Result(Nil, String) {
  let db = node.get_primary(ctx)
  
  // Ensure base market schema is configured
  market.configure_tick_retention(db)
  
  // Configure graph and intelligence attributes
  let config = fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None)
  let _ = gleamdb.set_schema(db, "trades_with", config)
  let _ = gleamdb.set_schema(db, "insider/confidence", config)
  let _ = gleamdb.set_schema(db, "market/influences", config)
  let _ = gleamdb.set_schema(db, "market/name", config)

  // Enforce: Only one tick per (market, timestamp) pair
  let _ = gleamdb.register_composite(db, ["tick/market_id", "tick/timestamp"])
  
  // Enforce: Only one prediction per (market, timestamp) pair
  let _ = gleamdb.register_composite(db, ["prediction/market_id", "prediction/timestamp"])
  
  io.println("🔒 Composites: market tick + prediction uniqueness registered")
  
  // Seed graph data so scans have something to find (dogfooding)
  seed_graph_data(ctx)
  
  Ok(Nil)
}

// ─────────────────────────────────────────────────────────────────
// Phase 27: Speculative Soul — what-if simulation for paper trading
// ─────────────────────────────────────────────────────────────────

/// Simulate a hypothetical trade and score its impact WITHOUT persisting.
/// Uses `with_facts` to fork a speculative DbState.
pub fn simulate_trade(
  db: gleamdb.Db,
  trader_id: String,
  market_id: String,
  direction: String,
  amount: Float,
) -> Result(Float, String) {
  let state = gleamdb.get_state(db)
  let tid = fact.deterministic_uid(trader_id)
  let ts = erlang_system_time()
  
  // Speculative facts: inject a hypothetical trade into a non-persistent fork
  let spec_facts = [
    #(tid, "trade/market", fact.Str(market_id)),
    #(tid, "trade/direction", fact.Str(direction)),
    #(tid, "trade/amount", fact.Float(amount)),
    #(tid, "trade/timestamp", fact.Int(ts)),
    #(tid, "trades_with", fact.Ref(fact.EntityId(shard_key(market_id)))),
  ]
  
  case gleamdb.with_facts(state, spec_facts) {
    Ok(spec_res) -> {
      let speculative_state = spec_res.state
      // CORRECT DX: Query the speculative state (pure value) using engine.run
      // In learnings.md I noted this mismatch — here I solve it.
      let query = q.new()
        |> q.pagerank("node", "trades_with", "rank")
        |> q.to_clauses()

      let _spec_results = engine.run(speculative_state, query, [], None, None).rows
      
      io.println("🔮 Speculative: Simulated " <> direction <> " $" 
        <> float.to_string(amount) <> " on " <> market_id 
        <> " for trader " <> trader_id)
      
      // Return speculative score (in real use, would compare pre/post PageRank)
      Ok(amount *. 0.95)  // Simplified: 5% slippage estimate
    }
    Error(e) -> Error(e)
  }
}

// ─────────────────────────────────────────────────────────────────
// Phase 29: Chronos — bitemporal market replay
// ─────────────────────────────────────────────────────────────────

/// Ingest a tick with explicit valid_time for retroactive corrections.
pub fn ingest_tick_bitemporal(
  db: gleamdb.Db,
  market_id: String,
  price: Float,
  volume: Int,
  valid_time: Int,
) -> Result(Nil, String) {
  let lookup = fact.Lookup(#("tick/market_id", fact.Str(market_id)))
  let facts = [
    #(lookup, "tick/market_id", fact.Str(market_id)),
    #(lookup, "tick/price", fact.Float(price)),
    #(lookup, "tick/volume", fact.Int(volume)),
    #(lookup, "tick/timestamp", fact.Int(valid_time)),
  ]
  
  case gleamdb.transact_at(db, facts, valid_time) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(e)
  }
}

/// Replay market state as-of a specific valid time.
/// Answers: "What did we believe the market looked like at time T?"
pub fn replay_market_at(
  db: gleamdb.Db,
  market_id: String,
  valid_time: Int,
) -> List(types.QueryResult) {
  let query = q.new()
    |> q.where(q.v("t"), "tick/market_id", q.s(market_id))
    |> q.where(q.v("t"), "tick/price", q.v("price"))
    |> q.where(q.v("t"), "tick/timestamp", q.v("ts"))
    |> q.order_by("ts", types.Desc)
    |> q.limit(50)
    |> q.to_clauses()
  
  [gleamdb.as_of_valid(db, valid_time, query)]
}

// ─────────────────────────────────────────────────────────────────
// Phase 28: Navigator — verify cost-based planner
// ─────────────────────────────────────────────────────────────────

/// Print the query plan for a complex multi-join query.
/// The Navigator (Phase 28) automatically reorders joins for performance.
pub fn explain_complex_query() -> String {
  let query = q.new()
    |> q.where(q.v("t"), "trade/market", q.v("market"))
    |> q.where(q.v("t"), "trade/trader", q.v("trader"))
    |> q.where(q.v("trader"), "insider/confidence", q.v("conf"))
    |> q.where(q.v("market"), "market/name", q.v("name"))
    |> q.order_by("conf", types.Desc)
    |> q.limit(10)
    |> q.to_clauses()
  
  let plan = gleamdb.explain(query)
  io.println("📋 Query Plan:\n" <> plan)
  plan
}

// ─────────────────────────────────────────────────────────────────
// Phase 31: Sovereign Intelligence — distributed aggregates
// ─────────────────────────────────────────────────────────────────

/// Compute cross-market aggregate statistics using push-down predicates.
pub fn market_aggregate_stats(db: gleamdb.Db) -> types.QueryResult {
  // 1. Direct verify facts
  let direct_query = [types.Positive(#(types.Var("e"), "tick/probability", types.Var("v")))]
  let direct_res = gleamdb.query(db, direct_query).rows
  let count = list.length(direct_res)
  io.println("🛰️  DEBUG: Direct tick/probability count = " <> int.to_string(count))

  // 2. Simplified Aggregate Query (Phase 31)
  let avg_query = q.new()
    |> q.count("total_ticks", "t", [
      types.Positive(#(types.Var("t"), "tick/probability", types.Var("_p")))
    ])
    |> q.avg("avg_prob", "prob", [
      types.Positive(#(types.Var("t"), "tick/probability", types.Var("prob")))
    ])
    |> q.to_clauses()
  
  let results = gleamdb.query(db, avg_query)
  
  case list.first(results.rows) {
    Ok(row) -> {
      let avg = dict.get(row, "avg_prob") |> result.unwrap(fact.Float(0.0))
      let count = dict.get(row, "total_ticks") |> result.unwrap(fact.Int(0))
      io.println("📊 Aggregates: Avg Prob=" <> val_to_string(avg) 
        <> " | Total Ticks=" <> val_to_string(count))
    }
    _ -> {
       io.println("📊 Aggregates: No data returned from query")
       // If query returns empty but facts exist, the engine has a Phase 31 bug
       case count > 0 {
         True -> io.println("⚠️  ENGINE BUG: Facts exist but aggregates returned empty!")
         False -> io.println("ℹ️  No facts inhaled yet.")
       }
    }
  }
  
  results
}

// ─────────────────────────────────────────────────────────────────
// Phase 32: Graph Algorithm Suite — insider network analysis
// ─────────────────────────────────────────────────────────────────

/// Detect wash-trading rings: cycles in the "trades_with" graph.
pub fn detect_wash_trades(db: gleamdb.Db) -> types.QueryResult {
  // Direct verify graph facts
  let debug_query = [types.Positive(#(types.Var("e"), "trades_with", types.Var("v")))]
  let debug_res = gleamdb.query(db, debug_query).rows
  io.println("🛰️  DEBUG: trades_with count = " <> int.to_string(list.length(debug_res)))

  let query = q.new()
    |> q.cycle_detect("trades_with", "cycle")
    |> q.to_clauses()
  
  let results = gleamdb.query(db, query)
  let count = list.length(results.rows)
  
  case count > 0 {
    True -> io.println("🚨 WASH TRADE ALERT: " <> int.to_string(count) <> " trading rings detected!")
    False -> io.println("✅ No wash-trading rings detected")
  }
  
  results
}

/// Identify gatekeeper traders via betweenness centrality.
pub fn find_gatekeepers(db: gleamdb.Db) -> types.QueryResult {
  let query = q.new()
    |> q.betweenness_centrality("trades_with", "trader", "score")
    |> q.order_by("score", types.Desc)
    |> q.limit(5)
    |> q.to_clauses()
  
  let results = gleamdb.query(db, query)
  
  list.each(results.rows, fn(row) {
    let trader = dict.get(row, "trader") |> result.unwrap(fact.Str("?"))
    let score = dict.get(row, "score") |> result.unwrap(fact.Float(0.0))
    io.println("🎯 Gatekeeper: " <> val_to_string(trader) <> " | Centrality: " <> val_to_string(score))
  })
  
  results
}

/// Find tightly-coupled trading clusters using Tarjan's SCC.
pub fn find_trading_rings(db: gleamdb.Db) -> types.QueryResult {
  let query = q.new()
    |> q.strongly_connected_components("trades_with", "trader", "ring_id")
    |> q.to_clauses()
  
  let results = gleamdb.query(db, query)
  let count = list.length(results.rows)
  io.println("🔗 SCC Analysis: " <> int.to_string(count) <> " traders across trading rings")
  results
}

/// Map the insider influence network using PageRank + reachability.
pub fn insider_influence_map(db: gleamdb.Db, trader_id: String) -> types.QueryResult {
  let tid = fact.deterministic_uid(trader_id)
  
  let query = q.new()
    |> q.reachable(types.Val(fact.Ref(fact.EntityId(shard_key(trader_id)))), "trades_with", "reached")
    |> q.to_clauses()
  
  let results = gleamdb.query(db, query)
  let count = list.length(results.rows)
  let _ = tid
  io.println("🕸️ Influence Map: " <> trader_id <> " reaches " <> int.to_string(count) <> " traders")
  results
}

/// Order market dependencies using topological sort.
pub fn market_dependency_order(db: gleamdb.Db) -> types.QueryResult {
  let query = q.new()
    |> q.topological_sort("market/influences", "market", "order")
    |> q.order_by("order", types.Asc)
    |> q.to_clauses()
  
  let results = gleamdb.query(db, query)
  
  list.each(results.rows, fn(row) {
    let market = dict.get(row, "market") |> result.unwrap(fact.Str("?"))
    let order = dict.get(row, "order") |> result.unwrap(fact.Int(0))
    io.println("📈 Dependency Order: #" <> val_to_string(order) <> " → " <> val_to_string(market))
  })
  
  results
}

// ─────────────────────────────────────────────────────────────────
// Comprehensive scan — runs all analyses in sequence
// ─────────────────────────────────────────────────────────────────

/// Run the full intelligence scan. Exercises every GleamDB v2.0.0 feature.
pub fn full_intelligence_scan(ctx: ShardedContext) -> Nil {
  let db = node.get_primary(ctx)
  
  io.println("\n━━━━━ GleamDB v2.0.0 Intelligence Scan ━━━━━")
  
  // Phase 28: Show query plan
  let _ = explain_complex_query()
  
  // Phase 31: Aggregate stats
  let _ = market_aggregate_stats(db)
  
  // Phase 32: Graph intelligence
  let _ = detect_wash_trades(db)
  let _ = find_gatekeepers(db)
  let _ = find_trading_rings(db)
  let _ = market_dependency_order(db)
  
  io.println("━━━━━ Scan Complete ━━━━━\n")
  Nil
}

/// Start a periodic intelligence scan.
pub fn start_periodic_scan(ctx: ShardedContext, interval_ms: Int) {
  process.spawn_unlinked(fn() {
    scan_loop(ctx, interval_ms)
  })
}

fn scan_loop(ctx: ShardedContext, interval_ms: Int) {
  // 10s grace period for live feeds and seeding to settle
  process.sleep(10000)
  full_intelligence_scan(ctx)
  process.sleep(interval_ms)
  scan_loop(ctx, interval_ms)
}

// ─────────────────────────────────────────────────────────────────
// Seed Data for v2.0.0 Scans
// ─────────────────────────────────────────────────────────────────

pub fn seed_graph_data(ctx: ShardedContext) {
  // Cycle: A -> B -> C -> A
  let trader_a = fact.deterministic_uid("trader_a")
  let trader_b = fact.deterministic_uid("trader_b")
  let trader_c = fact.deterministic_uid("trader_c")
  let trader_d = fact.deterministic_uid("trader_d")
  
  let facts = [
    #(trader_a, "trades_with", fact.Ref(fact.EntityId(shard_key("trader_b")))),
    #(trader_b, "trades_with", fact.Ref(fact.EntityId(shard_key("trader_c")))),
    #(trader_c, "trades_with", fact.Ref(fact.EntityId(shard_key("trader_a")))),
    
    // Gatekeeper: D -> A (D is outside the cycle but connected)
    #(trader_d, "trades_with", fact.Ref(fact.EntityId(shard_key("trader_a")))),
    
    // Insider Scores
    #(trader_a, "insider/confidence", fact.Float(0.85)),
    #(trader_b, "insider/confidence", fact.Float(0.45)),
    
    // Market Dependencies (for topo_sort)
    #(fact.deterministic_uid("m_btc"), "market/influences", fact.Ref(fact.EntityId(shard_key("m_eth")))),
    #(fact.deterministic_uid("m_eth"), "market/influences", fact.Ref(fact.EntityId(shard_key("m_sol")))),
    
    // Market Metadata for join testing
    #(fact.deterministic_uid("m_btc"), "market/name", fact.Str("Bitcoin")),
    #(fact.deterministic_uid("m_eth"), "market/name", fact.Str("Ethereum")),
    #(fact.deterministic_uid("m_sol"), "market/name", fact.Str("Solana"))
  ]
  
  let db = node.get_primary(ctx)
  let _ = gleamdb.transact(db, facts)
  io.println("🎲 Seeding v2.0.0 graph data for dogfooding scans...")
}

// ─────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────

fn val_to_string(val: fact.Value) -> String {
  case val {
    fact.Str(s) -> s
    fact.Int(i) -> int.to_string(i)
    fact.Float(f) -> float.to_string(f)
    fact.Ref(fact.EntityId(id)) -> "e:" <> int.to_string(id)
    _ -> "<?>"
  }
}

fn shard_key(id: String) -> Int {
  // Simple deterministic hash for entity routing
  erlang_phash2(id)
}

@external(erlang, "erlang", "system_time")
fn do_system_time(unit: Int) -> Int

fn erlang_system_time() -> Int {
  do_system_time(1000)
}

@external(erlang, "erlang", "phash2")
fn erlang_phash2(term: String) -> Int
