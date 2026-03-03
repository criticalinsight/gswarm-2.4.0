import gleeunit/should
import gleam/erlang/process
import gleam/list
import gleam/dict
import gswarm/node
import gswarm/fabric
import gswarm/market
import gswarm/sharded_query
import gswarm/ingest_batcher
import gswarm/shard_manager
import gswarm/registry_actor
import gswarm/insider_store
import gleamdb/shared/types.{Positive, Val, Var}
import gleamdb/fact
import gleamdb
pub fn bloom_integration_test() {
  // 1. Setup Sharded Context with 2 shards
  let assert Ok(ctx) = fabric.join_sharded_fabric(node.Leader, "test_bloom_shards", 2)
  
  // 2. Start Batchers (passing insider_actor required for Phase 49)
  let assert Ok(insider_actor) = insider_store.start(get_shard(ctx, 0))
  let assert Ok(batcher0) = ingest_batcher.start(get_shard(ctx, 0), ctx.registry_actor, insider_actor)
  let assert Ok(batcher1) = ingest_batcher.start(get_shard(ctx, 1), ctx.registry_actor, insider_actor)
  
  let m1 = "market_test_1"
  let _ = market.create_prediction_market(get_shard(ctx, shard_manager.get_shard_id(m1, 2)), market.Market(
    id: m1,
    question: "Test Market",
    outcomes: ["YES", "NO"],
    market_type: market.Binary,
    status: market.Open,
    close_time: 2000000000,
    source: "test"
  ))

  // 3. Ingest tick for market m1
  let tick1 = market.PredictionTick(m1, "YES", 0.6, 100, 1000, "test_trader")
  let shard_id = shard_manager.get_shard_id(m1, 2)
  let target_batcher = case shard_id {
    0 -> batcher0
    _ -> batcher1
  }
  
  process.send(target_batcher, ingest_batcher.Ingest(tick1, [0.1, 0.2]))
  
  // Wait for batcher to update registry (async)
  process.sleep(200)
  
  // 4. Verify Bloom Filter reflects market_test_1 in the central registry
  let registry_reply = process.new_subject()
  process.send(ctx.registry_actor, registry_actor.GetRegistry(registry_reply))
  let assert Ok(registry) = process.receive(registry_reply, 100)
  shard_manager.market_might_exist(registry, m1) |> should.be_true()
  shard_manager.market_might_exist(registry, "non_existent") |> should.be_false()
  
  // 5. Test Sharded Query Pruning
  // Query for m1: should only ping target shard
  let query_m1 = [Positive(#(Var("m"), "market/id", Val(fact.Str(m1))))]
  let results = sharded_query.query_all(ctx, query_m1)
  // Initially results has 1 item (the market metadata we created)
  list.length(results.rows) |> should.equal(1)
  
  // Force Flush
  process.send(target_batcher, ingest_batcher.Flush)
  process.sleep(200)
  
  // Query ticks: Should find the tick now
  let tick_query = [Positive(#(Var("t"), "tick/market", Var("m"))), Positive(#(Var("m"), "market/id", Val(fact.Str(m1))))]
  let results_after = sharded_query.query_all(ctx, tick_query)
  { results_after.rows != [] } |> should.be_true()
  
  node.stop_sharded(ctx)
}

fn get_shard(ctx: node.ShardedContext, id: Int) -> gleamdb.Db {
  let assert Ok(db) = dict.get(ctx.db.shards, id)
  db
}
