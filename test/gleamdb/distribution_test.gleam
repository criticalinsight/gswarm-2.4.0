import gleam/list
import gleeunit/should
import gleamdb
import gleamdb/fact
import gleamdb/shared/types

pub fn distribution_test() {
  let db = gleamdb.new()
  
  // 1. Transaction on local db
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "name", fact.Str("Alice")),
    #(fact.Uid(fact.EntityId(1)), "age", fact.Int(30))
  ])
  
  // 2. Simple query
  let result = gleamdb.query(db, [
    gleamdb.p(#(types.Var("e"), "name", types.Var("n")))
  ])
  
  should.equal(list.length(result.rows), 1)
}
