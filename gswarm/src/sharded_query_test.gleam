import gleam/io
import gleam/list
import gleam/float
import gleam/option
import gleamdb/sharded
import gleamdb/fact

pub fn main() {
  io.println("🧪 Gswarm: Verifying Phase 50 Distributed V-Link...")
  
  // 1. Setup local sharded DB
  let cluster_id = "vlink_test"
  let shard_count = 2
  let assert Ok(db) = sharded.start_local_sharded(cluster_id, shard_count, option.None)
  
  // 2. Ingest vectors into different shards using deterministic hashing
  let facts = [
    #(fact.Uid(fact.EntityId(1)), "test/vec", fact.Vec([1.0, 0.0, 0.0])), // Shard 1 (1 % 2)
    #(fact.Uid(fact.EntityId(2)), "test/vec", fact.Vec([0.0, 1.0, 0.0])), // Shard 0 (2 % 2)
    #(fact.Uid(fact.EntityId(3)), "test/vec", fact.Vec([0.0, 0.0, 1.0])), // Shard 1 (3 % 2)
    #(fact.Uid(fact.EntityId(4)), "test/vec", fact.Vec([0.7, 0.7, 0.0]))  // Shard 0 (4 % 2)
  ]
  
  let _ = sharded.transact(db, facts)
  io.println("📥 Data ingested across " <> int_to_string(shard_count) <> " shards.")
  
  // 3. Perform Global Vector Search
  let query = [0.8, 0.6, 0.0]
  let threshold = 0.5
  let k = 2
  
  io.println("🔍 Searching for globally most similar vectors to [0.8, 0.6, 0.0]...")
  let results = sharded.global_vector_search(db, query, threshold, k)
  
  io.println("📊 Results:")
  list.each(results, fn(res) {
    io.println("  • Entity: " <> int_to_string(fact.eid_to_integer(res.entity)) <> " | Score: " <> float.to_string(res.score))
  })
  
  // Verify Top-1 (Entity 4 should be closest to [0.8, 0.6])
  case list.first(results) {
    Ok(res) -> {
      let id = fact.eid_to_integer(res.entity)
      case id == 4 {
        True -> io.println("✅ Global Top-1 correctly identified: Entity 4")
        False -> io.println("❌ Verification FAILED: Incorrect Top-1 result (Entity " <> int_to_string(id) <> ")")
      }
    }
    _ -> io.println("❌ Verification FAILED: No results found")
  }
}

import gleam/int
fn int_to_string(i: Int) -> String { int.to_string(i) }
