import gleam/option.{None}
import gleam/erlang/process
import gleam/io
import gleam/list
import gleeunit
import gleeunit/should
import gleamdb
import gleamdb/q
import gleamdb/fact
import gleamdb/shared/types.{Delta, Initial}

pub fn main() {
  gleeunit.main()
}

pub fn reactive_delta_test() {
  let db = gleamdb.new_with_adapter_and_timeout(None, 1000)
  
  // 1. Setup Data
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "chat/id", fact.Int(100)),
    #(fact.Uid(fact.EntityId(1)), "chat/msg", fact.Str("Hello"))
  ])
  
  // 2. Subscribe
  let query = q.select(["msg"])
    |> q.where(q.v("e"), "chat/id", q.i(100))
    |> q.where(q.v("e"), "chat/msg", q.v("msg"))
    |> q.to_clauses()
    
  let subject = process.new_subject()
  gleamdb.subscribe(db, query, subject)
  
  // 3. Assert Initial State
  let assert Ok(msg) = process.receive(subject, 1000)
  case msg {
    Initial(results) -> {
      should.equal(list.length(results.rows), 1)
    }
    _ -> should.fail()
  }
  
  // 4. Transact New Item
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(2)), "chat/id", fact.Int(100)),
    #(fact.Uid(fact.EntityId(2)), "chat/msg", fact.Str("World"))
  ])
  
  // 5. Assert Delta (Added)
  let assert Ok(msg2) = process.receive(subject, 1000)
  case msg2 {
    Delta(added, removed) -> {
      should.equal(list.length(added.rows), 1)
      should.equal(list.length(removed.rows), 0)
      io.println("Received Delta Added")
    }
    _ -> should.fail()
  }
  
  // 6. Retract Item
  // Note: Retract by entity ID or value?
  // We'll use retract API if available, or just use fact-based retraction if implemented?
  // GleamDB doesn't have `retract_entity` helper exposed yet?
  // `gleamdb.retract` takes List(Fact).
  let assert Ok(_) = gleamdb.retract(db, [
    #(fact.Uid(fact.EntityId(2)), "chat/msg", fact.Str("World"))
  ])
  
  // 7. Assert Delta (Removed)
  let assert Ok(msg3) = process.receive(subject, 1000)
  case msg3 {
    Delta(added, removed) -> {
      should.equal(list.length(added.rows), 0)
      should.equal(list.length(removed.rows), 1)
      io.println("Received Delta Removed")
    }
    _ -> should.fail()
  }
}
