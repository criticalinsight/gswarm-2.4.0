import gleam/dict
import gleam/list
import gleamdb
import gleamdb/fact.{Int, Str, Ref}
import gleamdb/shared/types.{Wildcard, PullMap, PullSingle}
import gleamdb/engine
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn speculative_test() {
  let db = gleamdb.new()
  
  // 1. Initial fact
  let assert Ok(state1) = gleamdb.transact(db, [#(fact.Uid(fact.EntityId(1)), "name", Str("Alice"))])
  
  // 2. Speculative fact
  let assert Ok(spec_res) = gleamdb.with_facts(state1, [#(fact.Uid(fact.EntityId(1)), "balance", Int(100))])
  let state2 = spec_res.state
  
  // 3. Verify state2 has both
  let _res2 = gleamdb.pull(db, fact.Uid(fact.EntityId(1)), [Wildcard])
  // Wait, gleamdb.pull takes Db (actor) and calls get_state. 
  // I need a way to pull from a DbState directly if I want to test speculative states easily via API.
  // Actually, engine.pull(state, ...) is what I should use.
  
  let res2 = engine.pull(state2, fact.Uid(fact.EntityId(1)), [Wildcard])
  let assert PullMap(m2) = res2
  dict.get(m2, "name") |> should.equal(Ok(PullSingle(Str("Alice"))))
  dict.get(m2, "balance") |> should.equal(Ok(PullSingle(Int(100))))
  
  // 4. Verify original actor state doesn't have it
  let res1 = gleamdb.pull(db, fact.Uid(fact.EntityId(1)), [Wildcard])
  let assert PullMap(m1) = res1
  dict.get(m1, "balance") |> should.equal(Error(Nil))
}

pub fn navigational_api_test() {
  let db = gleamdb.new()
  let eid = fact.EntityId(1)
  
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(eid), "name", Str("Alice")),
    #(fact.Uid(eid), "role", Str("Admin")),
    #(fact.Uid(eid), "role", Str("Editor"))
  ])
  
  gleamdb.get_one(db, fact.Uid(eid), "name") |> should.equal(Ok(Str("Alice")))
  let roles = gleamdb.get(db, fact.Uid(eid), "role")
  list.length(roles) |> should.equal(2)
  should.be_true(list.contains(roles, Str("Admin")))
  should.be_true(list.contains(roles, Str("Editor")))
}

pub fn pull_plus_test() {
  let db = gleamdb.new()
  let alice = fact.EntityId(1)
  let bob = fact.EntityId(2)
  
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(alice), "name", Str("Alice")),
    #(fact.Uid(alice), "secret", Str("password123")),
    #(fact.Uid(alice), "manager", Ref(bob)),
    #(fact.Uid(bob), "name", Str("Bob")),
    #(fact.Uid(bob), "manager", Int(3)) // Charlie as Int
  ])
  
  // 1. Except test
  let res = gleamdb.pull(db, fact.Uid(alice), gleamdb.pull_except(["secret"]))
  let assert PullMap(m) = res
  dict.get(m, "name") |> should.equal(Ok(PullSingle(Str("Alice"))))
  dict.get(m, "secret") |> should.equal(Error(Nil))
  
  // 2. Recursive test
  let res_rec = gleamdb.pull(db, fact.Uid(alice), gleamdb.pull_recursive("manager", 2))
  let assert PullMap(mr) = res_rec
  // mr should have alice's manager (Bob)
  let assert Ok(PullMap(mbob)) = dict.get(mr, "manager")
  dict.get(mbob, "name") |> should.equal(Ok(PullSingle(Str("Bob"))))
  // mbob should have charlie (id 3)
  let assert Ok(PullMap(mchar)) = dict.get(mbob, "manager")
  // mchar should be charlie's wildcard (since Recursion adds Wildcard at the end)
  // Charlie has no data yet, so PullMap([])
  should.equal(mchar, dict.new())
}

pub fn tx_id_func_test() {
  let db = gleamdb.new()
  
  gleamdb.register_function(db, "audit", fn(_state, tx_id, _vt, args) {
    case args {
      [Int(eid_int)] -> [#(fact.Uid(fact.EntityId(eid_int)), "last_modified_tx", Int(tx_id))]
      _ -> []
    }
  })
  
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "name", Str("Data")),
    #(fact.Lookup(#("db/fn", Str("audit"))), "any", fact.List([Int(1)]))
  ])
  
  gleamdb.get_one(db, fact.Uid(fact.EntityId(1)), "last_modified_tx") |> should.equal(Ok(Int(1)))
}
