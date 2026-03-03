import gleam/erlang/process
import gleam/option.{None, Some}
import gleam/dict
import gleam/list
import gleamdb
import gleamdb/cache
import gleamdb/sharded
import gleamdb/shared/types
import gleamdb/fact
import gleeunit/should

pub fn main() {
  cache_test()
  bloom_join_test()
}

pub fn cache_test() {
  let assert Ok(db) = gleamdb.start_link(None, 5000)
  let config =
    cache.CacheConfig(
      max_size: 10,
      invalidator: fn(d, k) {
        let fact.EntityId(eid_int) = d.entity
        let fact.EntityId(key_int) = k
        eid_int == key_int
      },
    )
  let assert Ok(c) = cache.start_reactive(db, config)

  // 1. Set and Get
  cache.set(c, fact.EntityId(1), "Result 1")
  process.sleep(50)
  cache.get(c, fact.EntityId(1)) |> should.equal(Some("Result 1"))

  // 2. Transact and Invalidate
  let _ = gleamdb.transact(db, [#(fact.uid(1), "test", fact.Int(100))])

  // Give some time for WAL to propagate
  process.sleep(100)

  cache.get(c, fact.EntityId(1)) |> should.equal(None)
}

pub fn bloom_join_test() {
  let assert Ok(db) = sharded.start_local_sharded("cluster_v16", 2, None)

  // Populate shards with some cross-shard joinable data
  // Entity 2 (even) -> Shard 0
  // Entity 1 (odd) -> Shard 1
  let _ =
    sharded.transact(db, [
      #(fact.uid(1), "follows", fact.Ref(fact.EntityId(2))),
      #(fact.uid(1), "name", fact.Str("User 1")),
      #(fact.uid(2), "age", fact.Int(25)),
      #(fact.uid(2), "name", fact.Str("User 2")),
    ])

  let probe = [
    types.Positive(#(types.Var("e1"), "follows", types.Var("e2"))),
    types.Positive(#(types.Var("e1"), "name", types.Var("n1"))),
  ]

  let build = [types.Positive(#(types.Var("e2"), "age", types.Var("age")))]

  let res = sharded.bloom_query(db, "e2", probe, build)

  list.length(res.rows) |> should.equal(1)
  let assert Ok(row) = list.first(res.rows)
  dict.get(row, "n1") |> should.equal(Ok(fact.Str("User 1")))
  dict.get(row, "age") |> should.equal(Ok(fact.Int(25)))
}
