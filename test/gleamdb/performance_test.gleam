import gleam/list
import gleam/int
import gleamdb
import gleamdb/fact.{Int}
import gleamdb/shared/types.{Rule, Val, Var}
import gleam/dict
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn join_optimization_test() {
  let db = gleamdb.new()
  
  // High cardinality data
  let facts = list.flat_map(int.range(from: 1, to: 101, with: [], run: fn(acc, i) { [i, ..acc] }) |> list.reverse(), fn(i) {
    [
      #(fact.Uid(fact.EntityId(i)), "type", Int(0)),
      #(fact.Uid(fact.EntityId(i)), "val", Int(i))
    ]
  })
  
  let assert Ok(_) = gleamdb.transact(db, facts)
  
  // Specific fact
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(101)), "type", Int(1)),
    #(fact.Uid(fact.EntityId(101)), "val", Int(999))
  ])
  
  // Query: Find entity of type 1 that has val V
  let result = gleamdb.query(db, [
    gleamdb.p(#(Var("e"), "type", Val(Int(1)))),
    gleamdb.p(#(Var("e"), "val", Var("v")))
  ])
  
  should.equal(result.rows, [dict.from_list([#("e", fact.Ref(fact.EntityId(101))), #("v", Int(999))])])
}

pub fn large_recursion_benchmark_test() {
  let db = gleamdb.new()
  
  // Linear graph of 50 nodes
  let facts = list.map(int.range(from: 1, to: 50, with: [], run: fn(acc, i) { [i, ..acc] }) |> list.reverse(), fn(i) {
    #(fact.Uid(fact.EntityId(i)), "parent", Int(i + 1))
  })
  
  let assert Ok(_) = gleamdb.transact(db, facts)
  
  let rules = [
    Rule(#(Var("A"), "ancestor", Var("B")), [
      gleamdb.p(#(Var("A"), "parent", Var("B")))
    ]),
    Rule(#(Var("A"), "ancestor", Var("C")), [
      gleamdb.p(#(Var("A"), "parent", Var("B"))),
      gleamdb.p(#(Var("B"), "ancestor", Var("C")))
    ])
  ]
  
  // Find all ancestors of 50. Should be 1..49.
  let result = gleamdb.query_with_rules(db, [
    gleamdb.p(#(Var("e"), "ancestor", Val(Int(50))))
  ], rules)
  
  should.equal(list.length(result.rows), 49)
}
