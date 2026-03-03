import gleam/list
import gleam/option.{Some}
import gleamdb/fact
import gleamdb/sharded
import gleamdb/storage
import gleamdb/shared/types
import gleeunit/should

pub fn sharded_hnsw_test() {
  // 1. Start sharded DB with 2 shards
  let assert Ok(db) = sharded.start_sharded("hnsw_cluster", 2, Some(storage.ephemeral()))
  
  // 2. Insert vectors into different shards using fact.Uid
  let facts = [
    #(fact.Uid(fact.EntityId(1)), "vec", fact.Vec([1.0, 0.0, 0.0])),
    #(fact.Uid(fact.EntityId(2)), "vec", fact.Vec([0.0, 1.0, 0.0])),
  ]
  
  let assert Ok(_) = sharded.transact(db, facts)
  
  // 3. Similarity Search across shards
  // Similarity(variable: String, vector: List(Float), threshold: Float)
  let query_clause = types.Similarity("v", [0.9, 0.1, 0.0], 0.8)
  let results = sharded.query(db, [query_clause])
  
  // Should find the vector [1.0, 0.0, 0.0] from Shard 0 (or 1 depending on hash)
  list.length(results.rows) |> should.equal(1)
  
  sharded.stop(db)
}
