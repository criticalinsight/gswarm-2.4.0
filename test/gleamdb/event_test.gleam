import gleam/option.{None}
import gleam/erlang/process
import gleam/list
import gleam/dict
import gleeunit
import gleeunit/should
import gleamdb
import gleamdb/q
import gleamdb/fact.{Str}
import gleamdb/event
import gleamdb/engine

pub fn main() {
  gleeunit.main()
}

pub fn event_assertion_test() {
  let db = gleamdb.new_with_adapter_and_timeout(None, 1000)
  
  // 1. Assert Event
  let assert Ok(_) = event.record(
    db, 
    "user/signup", 
    1707954000, 
    [#("user/email", Str("alice@example.com"))]
  )
  
  // 2. Query Event
  let state = gleamdb.get_state(db)
  let query = q.new()
    |> q.where(q.v("e"), "event/type", q.s("user/signup"))
    |> q.where(q.v("e"), "user/email", q.v("email"))
    |> q.to_clauses()
    
  let results = engine.run(state, query, [], None, None)
  should.equal(list.length(results.rows), 1)
  
  let assert Ok(binding) = list.first(results.rows)
  should.equal(dict.get(binding, "email"), Ok(Str("alice@example.com")))
}

pub fn event_idempotency_test() {
  let db = gleamdb.new_with_adapter_and_timeout(None, 1000)
  
  // Assert same event twice
  let ts = 1707954000
  let assert Ok(_) = event.record(db, "test/event", ts, [])
  let assert Ok(_) = event.record(db, "test/event", ts, [])
  
  // Query count - should only be one entity
  let state = gleamdb.get_state(db)
  let query = q.new()
    |> q.where(q.v("e"), "event/type", q.s("test/event"))
    |> q.to_clauses()
    
  let results = engine.run(state, query, [], None, None)
  should.equal(list.length(results.rows), 1)
}

pub fn event_reactive_test() {
  let db = gleamdb.new_with_adapter_and_timeout(None, 1000)
  let self_subject = process.new_subject()
  
  // 1. Setup Listener
  event.on_event(db, "trigger/me", fn(_state, eid) {
    process.send(self_subject, eid)
  })
  
  // 2. Assert Event
  process.sleep(100)
  let ts = 1707954001
  let assert Ok(_) = event.record(db, "trigger/me", ts, [])
  
  // 3. Wait for reaction
  let assert Ok(received_eid) = process.receive(self_subject, 5000)
  let expected_eid = fact.event_uid("trigger/me", ts)
  
  // Eid is an enum, we need to compare them
  case expected_eid, received_eid {
    fact.Uid(id1), fact.Uid(id2) -> should.equal(id1, id2)
    _, _ -> should.fail()
  }
}
