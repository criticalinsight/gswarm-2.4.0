import gleam/otp/actor
import gleam/erlang/process.{type Subject}
import gleam/dict
import gleam/list
import gleam/int
import gleam/io
import gleam/result
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/engine
import gleamdb/transactor

pub type Message {
  Stop
  Prune
}

pub type PrunerState {
  PrunerState(
    db: gleamdb.Db,
    retention_ms: Int,
    interval_ms: Int,
    timestamp_attr: String
  )
}

/// Start a background pruner that deletes facts older than retention_ms.
pub fn start(
  db: gleamdb.Db,
  retention_ms: Int,
  interval_ms: Int,
  timestamp_attr: String
) -> Result(Subject(Message), actor.StartError) {
  let state = PrunerState(db, retention_ms, interval_ms, timestamp_attr)
  
  actor.new(state)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) {
    let self = started.data
    // Start the periodic prune loop
    process.spawn(fn() {
      tick_loop(self, interval_ms)
    })
    self
  })
}

fn handle_message(state: PrunerState, msg: Message) -> actor.Next(PrunerState, Message) {
  case msg {
    Stop -> actor.stop()
    Prune -> {
      do_prune(state)
      actor.continue(state)
    }
  }
}

fn tick_loop(self: Subject(Message), interval: Int) {
  process.sleep(interval)
  process.send(self, Prune)
  tick_loop(self, interval)
}

fn do_prune(state: PrunerState) {
  let now = os_now_ms()
  let threshold = now - state.retention_ms
  
  // 1. Find entities with timestamp < threshold
  let query = [
    types.Positive(#(types.Var("e"), state.timestamp_attr, types.Var("ts")))
  ]
  let results = gleamdb.query(state.db, query)
  
  let candidates = list.filter_map(results.rows, fn(row) {
    case dict.get(row, "ts"), dict.get(row, "e") {
      Ok(fact.Int(ts)), Ok(e_val) if ts < threshold -> Ok(e_val)
      _, _ -> Error(Nil)
    }
  })
  
  case candidates {
    [] -> Nil
    _ -> {
      io.println("🧹 Pruner: Purging " <> int.to_string(list.length(candidates)) <> " expired entities from " <> state.timestamp_attr)
      
      list.each(candidates, fn(e_val) {
         // Pull all attributes to retract them fully
         let pattern = [engine.Wildcard]
         case e_val {
           fact.Ref(eid) -> {
             let pull_res = engine.pull(transactor.get_state(state.db), fact.Uid(eid), pattern)
             case pull_res {
               engine.Map(attrs) -> {
                 let facts_to_retract = dict.to_list(attrs)
                 |> list.map(fn(pair) {
                   let #(attr, val_res) = pair
                   let val = case val_res {
                     engine.Single(v) -> v
                     engine.Many([v, ..]) -> v
                     engine.Many([]) -> fact.Int(0)
                     _ -> fact.Int(0)
                   }
                   #(fact.Uid(eid), attr, val)
                 })
                 let _ = gleamdb.retract(state.db, facts_to_retract)
                 Nil
               }
               _ -> Nil
             }
           }
           _ -> Nil
         }
      })
    }
  }
}

@external(erlang, "os", "system_time")
fn os_now_ms_native() -> Int

fn os_now_ms() -> Int {
  os_now_ms_native() / 1_000_000
}
