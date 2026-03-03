import gleeunit/should
import gleam/dict
import gleam/list
import gleamdb
import gleamdb/fact.{Uid, EntityId, Ref}
import gleamdb/shared/types

// Define a rule: ?grandparent(gp, gc) :- parent(gp, p), parent(p, gc)
fn grandparent_rule() -> types.Rule {
  types.Rule(
    head: #(types.Var("gp"), "grandparent", types.Var("gc")),
    body: [
      types.Positive(#(types.Var("gp"), "parent", types.Var("p"))),
      types.Positive(#(types.Var("p"), "parent", types.Var("gc")))
    ]
  )
}

pub fn stored_rule_test() {
  let db = gleamdb.new()
  
  // 1. Store Rule
  let rule = grandparent_rule()
  let assert Ok(_) = gleamdb.store_rule(db, rule)
  
  // 2. Add Data
  let gp = Uid(EntityId(1))
  let p = Uid(EntityId(2))
  let _gc = Uid(EntityId(3))
  
  let assert Ok(_) = gleamdb.transact(db, [
    #(gp, "parent", Ref(EntityId(2))), // 1 is parent of 2
    #(p, "parent", Ref(EntityId(3))),  // 2 is parent of 3
  ])
  
  // 3. Query using the stored rule (implicit)
  // Query: ?(x, y) where grandparent(x, y)
  let query = [types.Positive(#(types.Var("x"), "grandparent", types.Var("y")))]
  
  // We don't pass any rules explicitly!
  let results = gleamdb.query_with_rules(db, query, [])
  
  list.length(results.rows) |> should.equal(1)
  let assert [res] = results.rows
  dict.get(res, "x") |> should.equal(Ok(Ref(EntityId(1))))
  dict.get(res, "y") |> should.equal(Ok(Ref(EntityId(3))))
}

pub fn rule_persistence_test() {
   // This test simulates recovery by relying on `apply_datom` logic we added.
   // Since `gleamdb.new()` uses ephemeral storage, we can't truly "restart" it easily 
   // without mocking storage or checking internal state directly.
   // Ideally, we check if `db` has the rule in `stored_rules` and `virtual_predicates`.
   
   let db = gleamdb.new()
   let rule = grandparent_rule()
   let assert Ok(_) = gleamdb.store_rule(db, rule)
   
   // We can verify persistence by checking if the rule acts as a fact in the DB history/logs?
   // Or just rely on the functional test above which implicitly tests that `store_rule` updated the `DbState`.
   // `store_rule` updates `DbState.stored_rules` AND persists a fact.
   
   // Let's verify the fact exists!
   let query_rule = [types.Positive(#(types.Var("e"), "_rule/content", types.Var("content")))]
   let results = gleamdb.query(db, query_rule)
   list.length(results.rows) |> should.equal(1)
}
