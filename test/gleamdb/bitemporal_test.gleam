import gleam/dict
import gleam/list
import gleam/option
import gleeunit/should
import gleamdb
import gleamdb/fact
import gleamdb/shared/types

pub fn bitemporal_basic_test() {
  let db = gleamdb.new()
  
  // 1. Assert fact for Valid Time 100
  let assert Ok(_) = gleamdb.transact_at(db, [
    #(fact.Uid(fact.EntityId(1)), "user/location", fact.Str("London"))
  ], 100)
  
  // 2. Query at Valid Time 50 (should be empty)
  let results_50 = gleamdb.as_of_valid(db, 50, [
    gleamdb.p(#(types.Var("e"), "user/location", types.Var("loc")))
  ])
  should.equal(list.length(results_50.rows), 0)
  
  // 3. Query at Valid Time 100 (should have London)
  let results_100 = gleamdb.as_of_valid(db, 100, [
    gleamdb.p(#(types.Var("e"), "user/location", types.Var("loc")))
  ])
  should.equal(list.length(results_100.rows), 1)
}

pub fn bitemporal_correction_test() {
  let db = gleamdb.new()
  
  // 0. Set location to be unique (cardinality one)
  let assert Ok(_) = gleamdb.set_schema(db, "user/location", fact.AttributeConfig(unique: True, component: False, retention: fact.All, cardinality: fact.One, check: option.None, composite_group: option.None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))

  // 1. We thought Rich was in London at VT=100
  let assert Ok(_) = gleamdb.transact_at(db, [
    #(fact.Uid(fact.EntityId(1)), "user/location", fact.Str("London"))
  ], 100)
  
  // 2. Later we discovered he was actually in Paris at VT=100
  let assert Ok(_) = gleamdb.transact_at(db, [
    #(fact.Uid(fact.EntityId(1)), "user/location", fact.Str("Paris"))
  ], 100)
  
  // 3. Query at latest TX, VT=100
  let results = gleamdb.as_of_valid(db, 100, [
    gleamdb.p(#(types.Var("e"), "user/location", types.Var("loc")))
  ])
  
  should.equal(list.length(results.rows), 1)
  let assert [res] = results.rows
  should.equal(dict.get(res, "loc"), Ok(fact.Str("Paris")))
}

pub fn bitemporal_proactive_test() {
  let db = gleamdb.new()
  
  // Assert a future promotion
  let assert Ok(_) = gleamdb.transact_at(db, [
    #(fact.Uid(fact.EntityId(1)), "user/role", fact.Str("CEO"))
  ], 2000000000) // Far future
  
  // Query now (simulated current time < 2B)
  let results_now = gleamdb.as_of_valid(db, 100, [
    gleamdb.p(#(types.Var("e"), "user/role", types.Var("r")))
  ])
  should.equal(list.length(results_now.rows), 0)
  
  // Query in future
  let results_future = gleamdb.as_of_valid(db, 2000000001, [
    gleamdb.p(#(types.Var("e"), "user/role", types.Var("r")))
  ])
  should.equal(list.length(results_future.rows), 1)
}
