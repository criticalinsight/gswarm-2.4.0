import gleam/io
import gleam/list
import gleam/int
import gleam/float
import gleam/dict
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gswarm/strategy.{type Strategy}

/// Selects the best strategy based on win rate from the last N verified predictions.
pub fn best_strategy(db: gleamdb.Db) -> #(String, Strategy) {
  // 1. Query verified prediction results
  let query = [
    types.Positive(#(types.Var("p"), "prediction/status", types.Val(fact.Str("verified")))),
    types.Positive(#(types.Var("p"), "prediction/strategy", types.Var("strat"))),
    types.Positive(#(types.Var("p"), "prediction/result", types.Var("res"))),
    types.Positive(#(types.Var("p"), "prediction/brier_score", types.Var("brier")))
  ]
  
  // Limiting to recent history would require sorting by timestamp, which we can add later.
  // For now, we aggregate all history.
  let results = gleamdb.query(db, query)
  io.println("StrategySelector: Found " <> int.to_string(list.length(results.rows)) <> " verification records.")
  
  // 2. Group by strategy and calculate stats
  let stats = list.fold(results.rows, dict.new(), fn(acc, row) {
    let strat_id = case dict.get(row, "strat") {
      Ok(fact.Str(s)) -> s
      _ -> "unknown"
    }
    
    let is_correct = case dict.get(row, "res") {
      Ok(fact.Str("correct")) -> True
      _ -> False
    }

    let brier = case dict.get(row, "brier") {
      Ok(fact.Float(b)) -> b
      _ -> 0.25 // Baseline for [0.5, 0.5] guess
    }
    
    let current_stats = case dict.get(acc, strat_id) {
      Ok(#(wins, total, brier_sum)) -> #(wins, total, brier_sum)
      Error(_) -> #(0, 0, 0.0)
    }
    
    let new_stats = case is_correct {
      True -> #(current_stats.0 + 1, current_stats.1 + 1, current_stats.2 +. brier)
      False -> #(current_stats.0, current_stats.1 + 1, current_stats.2 +. brier)
    }
    
    dict.insert(acc, strat_id, new_stats)
  })
  
  // 3. Find winner
  // 3. Find winner using "Wisdom Score" (Phase 51)
  // Wisdom = Win Rate / Avg Brier (Lower Brier is better)
  let best = dict.fold(stats, #("mean_reversion", -1.0), fn(current_best, strat_id, s) {
    let #(wins, total, brier_sum) = s
    let win_rate = int.to_float(wins) /. int.to_float(total)
    let avg_brier = brier_sum /. int.to_float(total)
    
    // Wisdom Score (Higher is better)
    // We add 0.01 to avoid div by zero, though Brier for incorrect is > 0
    let wisdom_score = win_rate /. float.max(0.1, avg_brier)
    
    // Minimum 5 samples to qualify
    case total >= 5 {
      True -> {
        case wisdom_score >. current_best.1 {
          True -> #(strat_id, wisdom_score)
          False -> current_best
        }
      }
      False -> current_best
    }
  })
  
  io.println("🧠 StrategySelector: Wisdom Winner is " <> best.0 <> " (Wisdom: " <> float.to_string(best.1) <> ")")
  
  #(best.0, strategy.from_string(best.0))
}
