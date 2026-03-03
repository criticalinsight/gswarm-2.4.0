import gleam/io
import gleam/int
import gleam/list
import gleam/erlang/process.{type Subject}
import gleamdb
import gleamdb/fact
import gleamdb/shared/types.{type ReactiveDelta, Delta, Initial, Val, Var}

pub fn spawn_price_watcher(db: gleamdb.Db) {
  process.spawn_unlinked(fn() {
    let subject = process.new_subject()
    
    // Subscribe to any price update (where attribute is "tick/price/Yes")
    let query = [
      gleamdb.p(#(Var("e"), "tick/price/Yes", Var("price")))
    ]
    
    gleamdb.subscribe(db, query, subject)
    
    io.println("🔔 Reflex: Watcher spawned and subscribed to prices.")
    watcher_loop(subject)
  })
}

fn watcher_loop(subject: Subject(ReactiveDelta)) {
  let assert Ok(delta) = process.receive(subject, 100000) // Watch forever
  
  case delta {
    Initial(results) -> {
      io.println("🔔 Reflex: Initial state observed (" <> int.to_string(list.length(results.rows)) <> " items)")
    }
    Delta(added, _removed) -> {
      case list.is_empty(added.rows) {
        True -> Nil
        False -> {
           io.println("🔔 Reflex: 🚨 New Price Detected! Batch size: " <> int.to_string(list.length(added.rows)))
        }
      }
    }
  }
  
  watcher_loop(subject)
}

pub fn spawn_market_watcher(db: gleamdb.Db, market_id: String) {
  process.spawn_unlinked(fn() {
    let subject = process.new_subject()
    
    // Subscribe only to price updates for a specific market entity
    let query = [
      gleamdb.p(#(Var("m"), "market/id", Val(fact.Str(market_id)))),
      gleamdb.p(#(Var("m"), "tick/price/Yes", Var("price")))
    ]
    
    gleamdb.subscribe(db, query, subject)
    
    io.println("🔔 Reflex [" <> market_id <> "]: Watcher spawned.")
    market_watcher_loop(market_id, subject)
  })
}

fn market_watcher_loop(market_id: String, subject: Subject(ReactiveDelta)) {
  let assert Ok(delta) = process.receive(subject, 100000)
  
  case delta {
    Initial(_) -> Nil
    Delta(added, _removed) -> {
      case list.is_empty(added.rows) {
        True -> Nil
        False -> {
           io.println("🔔 Reflex [" <> market_id <> "]: 🚨 New Price Detected! Batch size: " <> int.to_string(list.length(added.rows)))
        }
      }
    }
  }
  
  market_watcher_loop(market_id, subject)
}

pub fn spawn_multi_market_watcher(db: gleamdb.Db, market_a: String, market_b: String) {
  process.spawn_unlinked(fn() {
    let subject = process.new_subject()
    
    // Subscribe to a cross-market join:
    // Only trigger if we find prices for both markets
    let query = [
      gleamdb.p(#(Var("ma"), "market/id", Val(fact.Str(market_a)))),
      gleamdb.p(#(Var("ta"), "market/id", Var("ma"))),
      gleamdb.p(#(Var("ta"), "tick/price/Yes", Var("pa"))),
      
      gleamdb.p(#(Var("mb"), "market/id", Val(fact.Str(market_b)))),
      gleamdb.p(#(Var("tb"), "market/id", Var("mb"))),
      gleamdb.p(#(Var("tb"), "tick/price/Yes", Var("pb"))),
    ]
    
    gleamdb.subscribe(db, query, subject)
    
    io.println("🔔 Reflex: Cross-Market Join Watcher spawned for " <> market_a <> " & " <> market_b)
    watcher_loop(subject)
    watcher_loop(subject)
  })
}

pub fn spawn_prediction_watcher(db: gleamdb.Db, market_id: String) {
  process.spawn_unlinked(fn() {
    let subject = process.new_subject()
    
    // Subscribe to probability updates (any outcome)
    // We start with "YES" but ideally should watch all?
    // Let's watch "tick/probability/YES" for now as primary signal.
    let query = [
      gleamdb.p(#(types.Var("m"), "market/id", types.Val(fact.Str(market_id)))),
      gleamdb.p(#(types.Var("m"), "tick/probability/YES", types.Var("prob")))
    ]
    
    gleamdb.subscribe(db, query, subject)
    
    io.println("🔔 Reflex [" <> market_id <> "]: Prediction Watcher spawned.")
    prediction_watcher_loop(market_id, subject)
  })
}

fn prediction_watcher_loop(market_id: String, subject: Subject(types.ReactiveDelta)) {
  let assert Ok(delta) = process.receive(subject, 100000)
  
  case delta {
    types.Initial(_) -> Nil
    types.Delta(added, _removed) -> {
      case list.is_empty(added.rows) {
        True -> Nil
        False -> {
           io.println("🔔 Reflex [" <> market_id <> "]: 🔮 Probability Update! Batch size: " <> int.to_string(list.length(added.rows)))
        }
      }
    }
  }
  
  prediction_watcher_loop(market_id, subject)
}
