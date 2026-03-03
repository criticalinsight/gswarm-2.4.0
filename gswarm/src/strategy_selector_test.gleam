import gleam/io
import gleam/list
import gleamdb
import gleamdb/fact
import gswarm/strategy_selector

pub fn main() {
  io.println("🧪 Gswarm: Verifying Phase 51 Self-Correction Loop...")
  
  // 1. Setup local DB
  let db = gleamdb.new()
  
  // 2. Mock some verification records
  // Strategy A: 80% Win Rate, but poor calibration (High Brier Score = 0.4)
  // Strategy B: 70% Win Rate, but excellent calibration (Low Brier Score = 0.05)
  
  let records_a = list.repeat(Nil, 10) |> list.index_map(fn(_, idx) {
    let i = idx + 1
    let id = "pred_a_" <> int_to_string(i)
    let eid = fact.deterministic_uid(id)
    let is_win = i <= 8
    [
      #(eid, "prediction/id", fact.Str(id)),
      #(eid, "prediction/status", fact.Str("verified")),
      #(eid, "prediction/strategy", fact.Str("trend_following")),
      #(eid, "prediction/result", case is_win { True -> fact.Str("correct") False -> fact.Str("incorrect") }),
      #(eid, "prediction/brier_score", fact.Float(0.4))
    ]
  }) |> list.flatten
  
  let records_b = list.repeat(Nil, 10) |> list.index_map(fn(_, idx) {
    let i = idx + 1
    let id = "pred_b_" <> int_to_string(i)
    let eid = fact.deterministic_uid(id)
    let is_win = i <= 7
    [
      #(eid, "prediction/id", fact.Str(id)),
      #(eid, "prediction/status", fact.Str("verified")),
      #(eid, "prediction/strategy", fact.Str("mean_reversion")),
      #(eid, "prediction/result", case is_win { True -> fact.Str("correct") False -> fact.Str("incorrect") }),
      #(eid, "prediction/brier_score", fact.Float(0.05))
    ]
  }) |> list.flatten
  
  let _ = gleamdb.transact(db, list.append(records_a, records_b))
  io.println("📥 Training data (Mocked) ingested.")
  
  // 3. Select best strategy
  let #(best_id, _) = strategy_selector.best_strategy(db)
  
  // Expected: mean_reversion (Strategy B) should win because of calibration
  // Trend Following Wisdom = 0.8 / 0.4 = 2.0
  // Mean Reversion Wisdom = 0.7 / 0.1 (capped min) = 7.0
  
  case best_id == "mean_reversion" {
    True -> io.println("✅ Self-Correction Logic PASS: Calibration-aware winner selected.")
    False -> io.println("❌ Self-Correction Logic FAIL: Calibration ignored.")
  }
}

import gleam/int
fn int_to_string(i: Int) -> String { int.to_string(i) }
