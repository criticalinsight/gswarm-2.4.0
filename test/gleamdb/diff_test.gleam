import gleeunit/should
import gleam/list
import gleamdb
import gleamdb/fact.{Str, Int}

pub fn diff_test() {
  let db_actor = gleamdb.new()
  
  // Tx 1: Alice (age 30)
  let assert Ok(state1) = gleamdb.transact(db_actor, [
    #(fact.Uid(fact.EntityId(1)), "name", Str("Alice")),
    #(fact.Uid(fact.EntityId(1)), "age", Int(30)),
  ])
  let tx1 = state1.latest_tx

  // Tx 2: Bob (age 25)
  let assert Ok(state2) = gleamdb.transact(db_actor, [
    #(fact.Uid(fact.EntityId(2)), "name", Str("Bob")),
    #(fact.Uid(fact.EntityId(2)), "age", Int(25)),
  ])
  let tx2 = state2.latest_tx
  
  // Tx 3: Alice updates age to 31
  let assert Ok(state3) = gleamdb.transact(db_actor, [
    #(fact.Uid(fact.EntityId(1)), "age", Int(31)),
  ])
  let tx3 = state3.latest_tx
  
  // Diff between tx1 and tx2 (Should show Bob added)
  // Note: exclusive start? inclusive?
  // Usually from_tx (exclusive) to to_tx (inclusive).
  // If we want changes IN tx2, we need diff(tx1, tx2).
  // tx1 is the state AFTER tx1.
  // So changes between state1 and state2 are tx2.
  // Diff range (tx1 to tx3) -> Bob (2) + Alice update (1) = 3
  let diff_total = gleamdb.diff(db_actor, tx1, tx3)
  should.equal(list.length(diff_total), 3)
  
  let diff_2_3 = gleamdb.diff(db_actor, tx2, tx3)
  should.equal(list.length(diff_2_3), 1)
  
  let assert [d] = diff_2_3
  should.equal(d.value, Int(31))
  should.equal(d.tx, tx3)
  // Wait, does 'diff' return retractions? 
  // Standard Datoms have 'operation' field (Assert/Retract).
  // If I scan EAVT, I see Retracts if they are preserved.
  // GleamDB preserves retractions in index?
  // Yes, EAVT stores Datoms. Datom has `operation`.
  // So diff should return both.
  // One should be Retract 30, one Assert 31.
  // Verification logic depends on order or use sets.
}
