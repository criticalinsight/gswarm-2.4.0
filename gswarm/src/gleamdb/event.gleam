import gleam/erlang/process.{type Subject}
import gleam/dict
import gleam/list
import gleamdb/fact.{type Eid, type Value, Str, Int, Ref, Uid}
import gleamdb/transactor.{type Db}
import gleamdb/shared/types.{type DbState, type ReactiveDelta, Delta, Initial}
import gleamdb/q
import gleamdb

/// Records a new event into the database.
/// An event is modeled as an entity with a type, timestamp, and optional payload attributes.
pub fn record(
  db: Db,
  event_type: String,
  timestamp: Int,
  payload: List(#(String, Value)),
) -> Result(DbState, String) {
  let eid = fact.event_uid(event_type, timestamp)
  
  let event_facts = [
    #(eid, "event/type", Str(event_type)),
    #(eid, "event/timestamp", Int(timestamp)),
    ..list.map(payload, fn(p) { #(eid, p.0, p.1) })
  ]
  
  transactor.transact(db, event_facts)
}

/// Convenience function to create an event listener.
/// This subscribes to the database's reactive system for assertions of the specified event type.
pub fn on_event(
  db: Db,
  event_type: String,
  callback: fn(DbState, Eid) -> Nil,
) -> Subject(ReactiveDelta) {
  // Use a proxy subject that we return, but we'll spawn the actual receiver
  let proxy = process.new_subject()
  
  process.spawn(fn() {
    let sub = process.new_subject()
    
    let query = q.new()
      |> q.where(q.v("e"), "event/type", q.s(event_type))
      |> q.to_clauses()
      
    gleamdb.subscribe(db, query, sub)
    
    event_loop(sub, callback, db, proxy)
  })
  
  proxy
}

fn event_loop(
  sub: Subject(ReactiveDelta),
  callback: fn(DbState, Eid) -> Nil,
  db: Db,
  proxy: Subject(ReactiveDelta),
) {
  case process.receive_forever(sub) {
    Initial(results) -> {
      let state = transactor.get_state(db)
      process_results(results, state, callback)
      process.send(proxy, Initial(results))
      event_loop(sub, callback, db, proxy)
    }
    Delta(added, removed) -> {
      let state = transactor.get_state(db)
      process_results(added, state, callback)
      process.send(proxy, Delta(added, removed))
      event_loop(sub, callback, db, proxy)
    }
  }
}

fn process_results(
  results: types.QueryResult,
  state: DbState,
  callback: fn(DbState, Eid) -> Nil,
) {
  list.each(results.rows, fn(binding) {
    case dict.get(binding, "e") {
      Ok(Ref(eid)) -> {
        callback(state, Uid(eid))
      }
      _ -> Nil
    }
  })
}
