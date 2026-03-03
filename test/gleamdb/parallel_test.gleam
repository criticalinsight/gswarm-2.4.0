import gleeunit/should
import gleam/list

import gleamdb
import gleamdb/fact.{Int}
import gleamdb/shared/types

pub fn parallel_execution_test() {
  let db = gleamdb.new()
  
  // 1. Insert 600 facts to exceed 500 threshold
  let facts = range(1, 600) |> list.map(fn(i) {
    #(fact.Uid(fact.EntityId(i)), "val", Int(i))
  })
  let assert Ok(_) = gleamdb.transact(db, facts)
  
  // 2. Query all values > 0 (should match all)
  // This produces 600 contexts.
  // Then typically next clause would process them.
  // To trigger do_solve_clauses parallelism we need existing contexts to be > 500.
  // The first clause matches all. The second clause (e.g. filter) would process them.
  
  let result = gleamdb.query(db, [
    gleamdb.p(#(types.Var("e"), "val", types.Var("v"))),
    types.Filter(types.Gt(types.Var("v"), types.Val(fact.Int(0)))) // Simple filter to force processing
  ])
  
  should.equal(list.length(result.rows), 600)
}

fn range(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}
  // Order might depend on index iteration, but usually inserted order if index preserves it.
  // Here we just check we got 600.

