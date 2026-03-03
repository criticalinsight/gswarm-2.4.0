import gleam/list
import gleam/dict
import gleeunit
import gleeunit/should
import gleamdb
import gleamdb/fact.{Int}
import gleamdb/shared/types

pub fn main() {
  gleeunit.main()
}

pub fn negation_test() {
  let db = gleamdb.new()
  
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "name", fact.Str("Alice")),
    #(fact.Uid(fact.EntityId(2)), "name", fact.Str("Bob")),
    #(fact.Uid(fact.EntityId(3)), "name", fact.Str("Charlie")),
    #(fact.Uid(fact.EntityId(1)), "parent", Int(2)),
  ])
  
  let result = gleamdb.query(db, [
    gleamdb.p(#(types.Var("e"), "name", types.Var("n"))),
    types.Negative(#(types.Var("e"), "parent", types.Var("child")))
  ])
  
  should.equal(list.length(result.rows), 2)
  should.be_true(list.contains(result.rows, dict.from_list([#("e", fact.Ref(fact.EntityId(2))), #("n", fact.Str("Bob"))])))
  should.be_true(list.contains(result.rows, dict.from_list([#("e", fact.Ref(fact.EntityId(3))), #("n", fact.Str("Charlie"))])))
  should.be_false(list.contains(result.rows, dict.from_list([#("e", fact.Ref(fact.EntityId(1))), #("n", fact.Str("Alice"))])))
}

pub fn aggregation_test() {
  let db = gleamdb.new()
  
  // Setup data for aggregation
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "user/age", fact.Int(25)),
    #(fact.Uid(fact.EntityId(2)), "user/age", fact.Int(35)),
    #(fact.Uid(fact.EntityId(3)), "user/age", fact.Int(45))
  ])
  
  // 1. Count
  let res_count = gleamdb.query(db, [
    types.Aggregate("total", types.Count, "e", [
      gleamdb.p(#(types.Var("e"), "user/age", types.Var("a")))
    ])
  ])
  let assert Ok(row) = list.first(res_count.rows)
  should.equal(dict.get(row, "total"), Ok(fact.Int(3)))
  
  // 2. Sum
  let res_sum = gleamdb.query(db, [
    types.Aggregate("sum_age", types.Sum, "a", [
      gleamdb.p(#(types.Var("e"), "user/age", types.Var("a")))
    ])
  ])
  let assert Ok(row2) = list.first(res_sum.rows)
  should.equal(dict.get(row2, "sum_age"), Ok(fact.Int(105)))
  
  // 3. Min/Max
  let res_min_max = gleamdb.query(db, [
    types.Aggregate("min_age", types.Min, "a", [
      gleamdb.p(#(types.Var("e"), "user/age", types.Var("a")))
    ]),
    types.Aggregate("max_age", types.Max, "a", [
      gleamdb.p(#(types.Var("e"), "user/age", types.Var("a")))
    ])
  ])
  let assert Ok(row3) = list.first(res_min_max.rows)
  should.equal(dict.get(row3, "min_age"), Ok(fact.Int(25)))
  should.equal(dict.get(row3, "max_age"), Ok(fact.Int(45)))
}

pub fn advanced_aggregation_test() {
  let db = gleamdb.new()
  
  // 1. Setup Data: Users with ages 20, 30, 40
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "user/age", fact.Int(20)),
    #(fact.Uid(fact.EntityId(2)), "user/age", fact.Int(30)),
    #(fact.Uid(fact.EntityId(3)), "user/age", fact.Int(40))
  ])
  
  // 2. Avg Test
  let res_avg = gleamdb.query(db, [
    types.Aggregate("avg", types.Avg, "a", [
      gleamdb.p(#(types.Var("e"), "user/age", types.Var("a")))
    ])
  ])
  should.equal(res_avg.rows, [dict.from_list([#("avg", fact.Float(30.0))])])
  
  // 3. Median Test (Odd length)
  let res_med_odd = gleamdb.query(db, [
    types.Aggregate("med", types.Median, "a", [
      gleamdb.p(#(types.Var("e"), "user/age", types.Var("a")))
    ])
  ])
  should.equal(res_med_odd.rows, [dict.from_list([#("med", fact.Int(30))])])
  
  // 4. Median Test (Even length): Add age 32 -> [20, 30, 32, 40] -> Median = (30+32)/2 = 31.0
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(4)), "user/age", fact.Int(32))
  ])
  
  let res_med_even = gleamdb.query(db, [
    types.Aggregate("med", types.Median, "a", [
      gleamdb.p(#(types.Var("e"), "user/age", types.Var("a")))
    ])
  ])
  should.equal(res_med_even.rows, [dict.from_list([#("med", fact.Float(31.0))])])
}

pub fn query_state_test() {
  let db = gleamdb.new()
  let state = gleamdb.get_state(db)
  
  // Speculative facts
  let facts = [
    #(fact.Uid(fact.EntityId(100)), "temp/data", fact.Str("secret"))
  ]
  
  let assert Ok(spec_res) = gleamdb.with_facts(state, facts)
  
  // Query persistent DB (should be empty)
  let res1 = gleamdb.query(db, [gleamdb.p(#(types.Var("e"), "temp/data", types.Var("d")))])
  should.equal(list.length(res1.rows), 0)
  
  // Query speculative state (should have data)
  let res2 = gleamdb.query_state(spec_res.state, [gleamdb.p(#(types.Var("e"), "temp/data", types.Var("d")))])
  should.equal(list.length(res2.rows), 1)
  let assert Ok(row) = list.first(res2.rows)
  should.equal(dict.get(row, "d"), Ok(fact.Str("secret")))
}
