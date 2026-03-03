import gleam/io
import gleam/int
import gleam/list
import gleamdb/shared/types
import gleamdb/fact
import gleamdb/sharded
import gswarm/node
import gswarm/sharded_query

pub fn main() {
  io.println("🏎️  Starting Sharded Temporal Benchmark...")
  
  // 1. Setup Sharded DB
  let res = node.start_sharded(node.Lean, "bench_cluster", 4)
  let assert Ok(ctx) = res
  
  // 2. Ingest 1000 facts
  // Use int.range to avoid deprecated list.range and reduce allocations
  let facts = int.range(0, 1001, [], fn(acc, i) {
     [#(fact.Uid(fact.EntityId(i)), "bench/val", fact.Int(i)), ..acc]
  })
  
  let _ = sharded.transact(ctx.db, facts)
  io.println("✅ Ingested 1000 facts.")
  
  // 3. Benchmark Native Temporal
  let start_native = system_time()
  let native_results = sharded_query.query_since(ctx, [
    types.Positive(#(types.Var("e"), "bench/val", types.Var("v")))
  ], 500)
  let end_native = system_time()
  
  // 4. Benchmark Legacy Filter
  let start_legacy = system_time()
  let legacy_results = sharded_query.query_all(ctx, [
    types.Positive(#(types.Var("e"), "bench/val", types.Var("v"))),
    types.Filter(types.Gt(types.Var("v"), types.Val(fact.Int(500))))
  ])
  let end_legacy = system_time()
  
  io.println("📊 Results:")
  io.println("   Native Temporal: " <> int.to_string(end_native - start_native) <> "ms (Rows: " <> int.to_string(list.length(native_results.rows)) <> ")")
  io.println("   Legacy Filter: " <> int.to_string(end_legacy - start_legacy) <> "ms (Rows: " <> int.to_string(list.length(legacy_results.rows)) <> ")")
  
  case {end_native - start_native} < {end_legacy - start_legacy} {
    True -> io.println("🚀 Native Temporal is faster!")
    False -> io.println("⚖️  Performance is comparable at this scale.")
  }
}

@external(erlang, "erlang", "system_time")
fn system_time_erl(unit: Int) -> Int

fn system_time() -> Int {
  system_time_erl(1000) // milliseconds
}
