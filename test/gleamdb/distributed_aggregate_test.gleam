import gleeunit/should
import gleam/dict
import gleam/list
import gleam/erlang/process
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/sharded

pub fn distributed_sum_test() {
  let db1 = gleamdb.new()
  let db2 = gleamdb.new()
  let shards = dict.from_list([#(0, db1), #(1, db2)])
  let sdb = sharded.ShardedDb(shards: shards, shard_count: 2, cluster_id: "test")

  // Transact data into shards
  // EntityId(1) -> 1 % 2 = 1 (Shard 1)
  // EntityId(2) -> 2 % 2 = 0 (Shard 0)
  let _ = sharded.transact(sdb, [#(fact.Uid(fact.EntityId(1)), "val", fact.Int(10))])
  let _ = sharded.transact(sdb, [#(fact.Uid(fact.EntityId(2)), "val", fact.Int(20))])
  let _ = sharded.transact(sdb, [#(fact.Uid(fact.EntityId(3)), "val", fact.Int(30))])
  let _ = sharded.transact(sdb, [#(fact.Uid(fact.EntityId(4)), "val", fact.Int(40))])

  // Query global sum
  let q = [
    types.Aggregate("total", types.Sum, "v", [
      types.Positive(#(types.Var("e"), "val", types.Var("v")))
    ])
  ]

  let res = sharded.query(sdb, q)
  
  // Coordinate reduction should merge results from Shard 0 and Shard 1
  list.length(res.rows) |> should.equal(1)
  
  let assert Ok(row) = list.first(res.rows)
  dict.get(row, "total") |> should.equal(Ok(fact.Int(100)))
}

pub fn distributed_count_test() {
  let db1 = gleamdb.new()
  let db2 = gleamdb.new()
  let shards = dict.from_list([#(0, db1), #(1, db2)])
  let sdb = sharded.ShardedDb(shards: shards, shard_count: 2, cluster_id: "test")

  let _ = sharded.transact(sdb, [#(fact.Uid(fact.EntityId(1)), "val", fact.Int(10))])
  let _ = sharded.transact(sdb, [#(fact.Uid(fact.EntityId(2)), "val", fact.Int(20))])
  let _ = sharded.transact(sdb, [#(fact.Uid(fact.EntityId(3)), "val", fact.Int(30))])

  // Query global count
  let q = [
    types.Aggregate("cnt", types.Count, "e", [
      types.Positive(#(types.Var("e"), "val", types.Var("_")))
    ])
  ]

  let res = sharded.query(sdb, q)
  
  list.length(res.rows) |> should.equal(1)
  let assert Ok(row) = list.first(res.rows)
  dict.get(row, "cnt") |> should.equal(Ok(fact.Int(3)))
}

pub fn distributed_wal_test() {
  let db = gleamdb.new()
  let self = process.new_subject()
  
  gleamdb.subscribe_wal(db, self)
  
  let _ = gleamdb.transact(db, [#(fact.Uid(fact.EntityId(1)), "test/wal", fact.Int(42))])
  
  let assert Ok(datoms) = process.receive(self, 1000)
  list.is_empty(datoms) |> should.be_false()
  let assert Ok(d) = list.first(datoms)
  d.attribute |> should.equal("test/wal")
  d.value |> should.equal(fact.Int(42))
}
