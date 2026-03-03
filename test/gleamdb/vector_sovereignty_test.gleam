import gleam/dict
import gleam/list
import gleamdb
import gleamdb/fact.{Str, Vec}
import gleamdb/shared/types.{Var}
import gleeunit/should

pub fn vector_similarity_test() {
  let db = gleamdb.new()
  
  // 1. Setup Data with Embeddings
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "doc/id", Str("tech-1")),
    #(fact.Uid(fact.EntityId(1)), "doc/embedding", Vec([1.0, 0.0, 0.0])),
    
    #(fact.Uid(fact.EntityId(2)), "doc/id", Str("art-1")),
    #(fact.Uid(fact.EntityId(2)), "doc/embedding", Vec([0.0, 1.0, 0.0])),
    
    #(fact.Uid(fact.EntityId(3)), "doc/id", Str("space-1")),
    #(fact.Uid(fact.EntityId(3)), "doc/embedding", Vec([0.9, 0.1, 0.0]))
  ])
  
  // 2. Query for similar documents to [0.85, 0.15, 0.0]
  // Threshold 0.9
  let query_vec = [0.85, 0.15, 0.0]
  let result = gleamdb.query(db, [
    gleamdb.p(#(Var("e"), "doc/id", Var("id"))),
    gleamdb.p(#(Var("e"), "doc/embedding", Var("v"))),
    types.Similarity("v", query_vec, 0.95)
  ])
  
  // Result should be space-1 and tech-1 (both very similar)
  should.equal(list.length(result.rows), 2)
  
  let ids = list.map(result.rows, fn(row) {
    let assert Ok(Str(id)) = dict.get(row, "id")
    id
  })
  
  should.be_true(list.contains(ids, "tech-1"))
  should.be_true(list.contains(ids, "space-1"))
}

pub fn vector_discovery_test() {
  let db = gleamdb.new()
  
  // 1. Setup Data
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "v", fact.Vec([1.0, 0.0])),
    #(fact.Uid(fact.EntityId(2)), "v", fact.Vec([0.0, 1.0])),
    #(fact.Uid(fact.EntityId(3)), "v", fact.Vec([0.95, 0.05]))
  ])
  
  // 2. Discovery Query: Find ?v and ?e where ?v is similar to [0.9, 0.1]
  // Note: ?v is unbound here!
  let results = gleamdb.query(db, [
    types.Similarity("v", [0.9, 0.1], 0.9),
    gleamdb.p(#(types.Var("e"), "v", types.Var("v")))
  ])
  
  // Should find entities 1 and 3
  should.equal(list.length(results.rows), 2)
  
  let es = list.map(results.rows, fn(row) {
    let assert Ok(fact.Ref(fact.EntityId(e))) = dict.get(row, "e")
    e
  })
  
  should.be_true(list.contains(es, 1))
  should.be_true(list.contains(es, 3))
}
