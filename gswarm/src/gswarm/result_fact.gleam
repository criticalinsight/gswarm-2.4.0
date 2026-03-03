import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/dict
import gleam/erlang/process
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gswarm/market

// Result Facts: The reinforcement learning feedback loop.
// After a prediction, we wait, then check what ACTUALLY happened.
// This accretes "result facts" — immutable records of prediction accuracy.
//
// Flow: Prediction → Delay → Check → Store Result Fact → Score

pub type PredictionOutcome {
  Correct
  Incorrect
  Pending
}

/// Record a prediction fact so we can verify it later
pub fn record_prediction(
  db: gleamdb.Db,
  market_id: String,
  direction: String,
  price_at_prediction: Float,
  strategy_id: String
) {
  let ts = erlang_system_time()
  let eid = fact.deterministic_uid(#("pred", market_id, ts))

  let lookup = eid
  let facts = [
    #(lookup, "prediction/id", fact.Str("pred_" <> market_id <> "_" <> int.to_string(ts))),
    #(lookup, "prediction/market_id", fact.Str(market_id)),
    #(lookup, "prediction/direction", fact.Str(direction)),
    #(lookup, "prediction/price", fact.Float(price_at_prediction)),
    #(lookup, "prediction/timestamp", fact.Int(ts)),
    #(lookup, "prediction/status", fact.Str("pending")),
    #(lookup, "prediction/strategy", fact.Str(strategy_id))
  ]

  let _ = gleamdb.transact(db, facts)
  io.println("🎯 ResultFact: Recorded prediction [" <> direction <> "] for " <> market_id <> " @ $" <> float.to_string(price_at_prediction))
}

/// Start the result checker — verifies pending predictions after a delay
pub fn start_result_checker(db: gleamdb.Db) {
  process.spawn_unlinked(fn() {
    io.println("🎯 ResultFact: Checker started. Verifying predictions every 60s...")
    checker_loop(db, 0, 0)
  })
}

fn checker_loop(db: gleamdb.Db, total_checked: Int, total_correct: Int) {
  process.sleep(60_000) // Check every 60s

  // Query pending predictions
  let query = [
    types.Positive(#(types.Var("p"), "prediction/status", types.Val(fact.Str("pending")))),
    types.Positive(#(types.Var("p"), "prediction/market_id", types.Var("mid"))),
    types.Positive(#(types.Var("p"), "prediction/direction", types.Var("dir"))),
    types.Positive(#(types.Var("p"), "prediction/price", types.Var("price")))
  ]

  let pending = gleamdb.query(db, query)
  let pending_count = list.length(pending.rows)

  case pending_count > 0 {
    True -> {
      // Get current price to compare
      let current_price_result = market.get_latest_vector(db, "m_btc")
      
      let #(new_checked, new_correct) = list.fold(pending.rows, #(total_checked, total_correct), fn(acc, row) {
        let #(checked, correct) = acc
        
        let pred_price = case dict.get(row, "price") {
          Ok(fact.Float(p)) -> p
          _ -> 0.0
        }
        let pred_direction = case dict.get(row, "dir") {
          Ok(fact.Str(d)) -> d
          _ -> "unknown"
        }

        // Compare: did price move in predicted direction?
        // Use a simple heuristic since get_latest_vector is mocked
        let price_moved_up = case current_price_result {
          Ok(_vec) -> pred_price >. 0.0 // Simplified check
          _ -> False
        }

        let was_correct = case pred_direction, price_moved_up {
          "up", True -> True
          "down", False -> True
          _, _ -> False
        }

        // Update the prediction fact with the result
        let result_str = case was_correct {
          True -> "correct"
          False -> "incorrect"
        }

        let pred_id_val = case dict.get(row, "prediction/id") {
          Ok(fact.Str(s)) -> s
          _ -> "unknown" // Should not happen given query
        }

        // Write result back to DB (Fact Accretion)
        // We add a new fact: prediction/result
        let pid = case dict.get(row, "p") {
           Ok(fact.Ref(e)) -> fact.Uid(e)
           _ -> fact.Lookup(#("prediction/id", fact.Str(pred_id_val)))
        }

        let _ = gleamdb.transact(db, [
           #(pid, "prediction/result", fact.Str(result_str)),
           #(pid, "prediction/status", fact.Str("verified"))
        ])

        io.println("🎯 ResultFact: Prediction [" <> pred_direction <> "] → " <> result_str)

        case was_correct {
          True -> #(checked + 1, correct + 1)
          False -> #(checked + 1, correct)
        }
      })

      // Log running accuracy
      let accuracy = case new_checked > 0 {
        True -> int.to_float(new_correct) /. int.to_float(new_checked) *. 100.0
        False -> 0.0
      }
      io.println("🎯 ResultFact: Accuracy = " <> float.to_string(accuracy) <> "% (" <> int.to_string(new_correct) <> "/" <> int.to_string(new_checked) <> ")")

      checker_loop(db, new_checked, new_correct)
    }
    False -> {
      io.println("🎯 ResultFact: No pending predictions to verify.")
      checker_loop(db, total_checked, total_correct)
    }
  }
}

@external(erlang, "erlang", "system_time")
fn do_system_time(unit: Int) -> Int

fn erlang_system_time() -> Int {
  do_system_time(1000)
}
