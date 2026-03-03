import gleeunit/should
import gleam/option.{None}
import gleam/list
import gleam/dict
import gleam/erlang/process
import gleamdb
import gleamdb/fact
import gleamdb/sharded
import gleamdb/shared/types

pub fn sharded_idempotency_test() {
  let cluster_id = "test_sharded_identity"
  let assert Ok(db) = sharded.start_sharded(cluster_id, 4, None)
  
  // 1. Create a deterministic fact
  let data = "market_123"
  let eid = fact.deterministic_uid(data)
  let f1 = #(eid, "test/status", fact.Str("Active"))
  
  // 2. Transact twice
  let assert Ok(_) = sharded.transact(db, [f1])
  let assert Ok(_) = sharded.transact(db, [f1])
  
  // 3. Query - should only see ONE entity with this ID across the cluster
  let q = [
    gleamdb.p(#(types.Var("e"), "test/status", types.Val(fact.Str("Active"))))
  ]
  let results = sharded.query(db, q)
  
  list.length(results.rows) |> should.equal(1)
  
  let _ = sharded.stop(db)
}

pub fn sharded_scaling_test() {
  let cluster_id = "test_sharded_scaling"
  // Parallelize across 8 shards
  let assert Ok(db) = sharded.start_sharded(cluster_id, 8, None)
  
  // Ingest data into different shards
  let facts = [
    #(fact.deterministic_uid("m1"), "val", fact.Int(1)),
    #(fact.deterministic_uid("m2"), "val", fact.Int(2)),
    #(fact.deterministic_uid("m3"), "val", fact.Int(3)),
    #(fact.deterministic_uid("m4"), "val", fact.Int(4))
  ]
  
  let assert Ok(_) = sharded.transact(db, facts)
  
  // Verify unified query
  let results = sharded.query(db, [gleamdb.p(#(types.Var("e"), "val", types.Var("v")))])
  list.length(results.rows) |> should.equal(4)
  
  let _ = sharded.stop(db)
}

pub fn sharded_edge_cases_test() {
  let cluster_id = "test_sharded_edge"
  let assert Ok(db) = sharded.start_sharded(cluster_id, 2, None)
  
  // 1. Empty transaction
  let assert Ok([]) = sharded.transact(db, [])
  
  // 2. Single shard cluster (modulo 1)
  let assert Ok(db1) = sharded.start_sharded(cluster_id <> "_1", 1, None)
  let f = #(fact.deterministic_uid("x"), "a", fact.Int(1))
  let assert Ok(_) = sharded.transact(db1, [f])
  let _ = sharded.stop(db1)
  
  // 3. Hashing different types
  fact.deterministic_uid(123) |> should.not_equal(fact.deterministic_uid(124))
  fact.deterministic_uid(["a", "b"]) |> should.not_equal(fact.deterministic_uid(["a", "c"]))
  
  // 4. Lookup hashing
  let l1 = fact.Lookup(#("email", fact.Str("bob@example.com")))
  let l2 = fact.Lookup(#("email", fact.Str("alice@example.com")))
  // Ensure they likely map to different shards or at least hash differently
  fact.phash2(l1) |> should.not_equal(fact.phash2(l2))
  
  let _ = sharded.stop(db)
}

pub fn sharded_stop_cleanup_test() {
  let cluster_id = "test_sharded_stop"
  let assert Ok(db) = sharded.start_sharded(cluster_id, 2, None)
  
  let shard_pids = list.map(dict.to_list(db.shards), fn(pair) {
     let #(_, shard_db) = pair
     let assert Ok(pid) = process.subject_owner(shard_db)
     pid
  })
  
  let _ = sharded.stop(db)
  
  // Pids should be dead
  list.each(shard_pids, fn(pid) {
    process.is_alive(pid) |> should.equal(False)
  })
}
