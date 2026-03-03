import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/dict
import gleam/erlang/process
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/dynamic/decode
import gleam/result
import gleamdb
import gleamdb/fact
import gleamdb/q
import gleamdb/shared/types.{type DbState}
import gswarm/reflexion

/// A market resolution record.
pub type Resolution {
  Resolution(
    market_id: String,
    winning_outcome: String,
    resolved_at: Int,
    brier_score: Float
  )
}

/// Brier Score: (predicted_probability - actual_outcome)²
/// actual = 1.0 if prediction matched resolution, 0.0 otherwise.
/// Lower is better. 0.0 = perfect calibration.
pub fn brier_score(predicted: Float, actual: Float) -> Float {
  let diff = predicted -. actual
  diff *. diff
}

/// Start the resolution checker loop.
/// Periodically checks tracked prediction markets for resolution, 
/// settles predictions, and computes Brier scores.
pub fn start_resolution_checker(db: gleamdb.Db, market_ids: List(String)) {
  process.spawn_unlinked(fn() {
    io.println("🏁 Resolution Checker: Monitoring " <> int.to_string(list.length(market_ids)) <> " markets")
    check_loop(db, market_ids)
  })
}

fn check_loop(db: gleamdb.Db, market_ids: List(String)) {
  process.sleep(60_000) // Check every 60s

  list.each(market_ids, fn(mid) {
    case check_resolution(mid) {
      Ok(resolution) -> {
        io.println("🏁 RESOLVED: " <> mid <> " → " <> resolution.winning_outcome)
        let _ = settle_market(db, mid, resolution)
        Nil
      }
      Error(_) -> Nil  // Not resolved yet, or API error
    }
  })

  check_loop(db, market_ids)
}

/// Check if a Manifold market has resolved.
fn check_resolution(market_id: String) -> Result(Resolution, String) {
  let url = "https://api.manifold.markets/v0/market/" <> market_id
  let req_result = request.to(url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req_result)

  case httpc.send(req) {
    Ok(resp) if resp.status == 200 -> decode_resolution(resp.body, market_id)
    Ok(resp) -> Error("API status " <> int.to_string(resp.status))
    Error(_) -> Error("HTTP failed")
  }
}

fn decode_resolution(json_str: String, market_id: String) -> Result(Resolution, String) {
  let decoder = {
    use is_resolved <- decode.optional_field("isResolved", False, decode.bool)
    use resolution <- decode.optional_field("resolution", "", decode.string)
    use probability <- decode.optional_field("probability", 0.5, decode.float)
    decode.success(#(is_resolved, resolution, probability))
  }

  case json.parse(from: json_str, using: decoder) {
    Ok(#(True, resolution, last_prob)) -> {
      // Compute Brier score: compare last probability to binary outcome
      let actual = case resolution {
        "YES" -> 1.0
        _ -> 0.0
      }
      let score = brier_score(last_prob, actual)
      Ok(Resolution(
        market_id: market_id,
        winning_outcome: resolution,
        resolved_at: erlang_system_time(),
        brier_score: score
      ))
    }
    Ok(#(False, _, _)) -> Error("Not resolved")
    Error(_) -> Error("Decode failed")
  }
}

/// Settle a market: store resolution facts, compute aggregate Brier score.
pub fn settle_market(db: gleamdb.Db, market_id: String, resolution: Resolution) -> Result(DbState, String) {
  // 1. Store resolution facts
  let lookup = fact.Lookup(#("market/id", fact.Str("pm_" <> market_id)))
  let resolution_facts = [
    #(lookup, "market/status", fact.Str("resolved:" <> resolution.winning_outcome)),
    #(lookup, "market/resolved_at", fact.Int(resolution.resolved_at)),
    #(lookup, "market/brier_score", fact.Float(resolution.brier_score))
  ]
  let _ = gleamdb.transact(db, resolution_facts)

  // 2. Score all predictions for this market
  let pred_query = [
    types.Positive(#(types.Var("p"), "prediction/market_id", types.Val(fact.Str("pm_" <> market_id)))),
    types.Positive(#(types.Var("p"), "prediction/market_id", types.Val(fact.Str("pm_" <> market_id)))),
    types.Positive(#(types.Var("p"), "prediction/predicted_probability", types.Var("prob"))),
    types.Positive(#(types.Var("p"), "prediction/direction", types.Var("dir"))),
    types.Positive(#(types.Var("p"), "prediction/context_vector", types.Var("vec"))),
    types.Positive(#(types.Var("p"), "prediction/id", types.Var("pid")))
  ]
  let predictions = gleamdb.query(db, pred_query)

  let actual_value = case resolution.winning_outcome {
    "YES" -> 1.0
    _ -> 0.0
  }

  let scores = list.filter_map(predictions.rows, fn(row) {
    case dict.get(row, "prob"), dict.get(row, "vec"), dict.get(row, "pid"), dict.get(row, "dir") {
      Ok(fact.Float(prob)), Ok(fact.Vec(vec)), Ok(fact.Str(pid)), Ok(fact.Str(dir)) -> {
        let score = brier_score(prob, actual_value)
        
        // PHASE 52: Semantic Reflexion Trigger
        // If prediction was worse than random guessing (0.25), analyze it.
        case score >. 0.25 {
          True -> {
             // We need to pass 'db' here, but reflexion needs 'db' too.
             // reflexion.analyze_failure(db, pid, market_id, vec, dir, resolution.winning_outcome)
             // Note: analyze_failure is side-effectual (writes to DB), so we just call it.
             reflexion.analyze_failure(db, pid, market_id, vec, dir, resolution.winning_outcome)
          }
          False -> Nil
        }
        
        Ok(score)
      }
      // Handle legacy predictions without vector
      Ok(fact.Float(prob)), _, _, _ -> {
         Ok(brier_score(prob, actual_value))
      }
      _, _, _, _ -> Error(Nil)
    }
  })

  let avg_brier = case scores != [] {
    True -> {
      let sum = list.fold(scores, 0.0, fn(acc, s) { acc +. s })
      sum /. int.to_float(list.length(scores))
    }
    False -> 0.0
  }

  io.println("📊 Brier Score [" <> market_id <> "]: "
    <> float.to_string(avg_brier)
    <> " (from " <> int.to_string(list.length(scores)) <> " predictions)"
    <> " | Winner: " <> resolution.winning_outcome)

  // 3. Store aggregate calibration fact
  let cal_lookup = fact.Lookup(#("calibration/market_id", fact.Str("pm_" <> market_id)))
  let cal_facts = [
    #(cal_lookup, "calibration/market_id", fact.Str("pm_" <> market_id)),
    #(cal_lookup, "calibration/avg_brier", fact.Float(avg_brier)),
    #(cal_lookup, "calibration/prediction_count", fact.Int(list.length(scores))),
    #(cal_lookup, "calibration/resolution", fact.Str(resolution.winning_outcome))
  ]
  gleamdb.transact(db, cal_facts)
}

/// Get calibration report: returns list of (market_id, avg_brier_score).
pub fn calibration_report(db: gleamdb.Db) -> List(#(String, Float)) {
  let query = [
    types.Positive(#(types.Var("c"), "calibration/market_id", types.Var("mid"))),
    types.Positive(#(types.Var("c"), "calibration/avg_brier", types.Var("brier")))
  ]
  let results = gleamdb.query(db, query)

  list.filter_map(results.rows, fn(row) {
    case dict.get(row, "mid"), dict.get(row, "brier") {
      Ok(fact.Str(mid)), Ok(fact.Float(b)) -> Ok(#(mid, b))
      _, _ -> Error(Nil)
    }
  })
}

@external(erlang, "erlang", "system_time")
fn do_system_time(unit: Int) -> Int

fn erlang_system_time() -> Int {
  do_system_time(1000)
}

/// Get top N best-calibrated markets (lowest Brier score).
/// Uses database-native Sort + Limit (Phase 23).
pub fn get_top_calibrated_markets(db: gleamdb.Db, n: Int) -> List(#(String, Float)) {
  let query = 
    q.new()
    |> q.where(types.Var("c"), "calibration/market_id", types.Var("mid"))
    |> q.where(types.Var("c"), "calibration/avg_brier", types.Var("brier"))
    |> q.order_by("brier", types.Asc)
    |> q.limit(n)
    |> q.to_clauses
    
  let results = gleamdb.query(db, query)

  list.filter_map(results.rows, fn(row) {
    case dict.get(row, "mid"), dict.get(row, "brier") {
      Ok(fact.Str(mid)), Ok(fact.Float(b)) -> Ok(#(mid, b))
      _, _ -> Error(Nil)
    }
  })
}
