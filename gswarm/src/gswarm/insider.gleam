import gleam/list
import gleam/float
import gleam/dict
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gswarm/market

/// A scoring of a trader's information advantage.
pub type AlphaScore {
  AlphaScore(
    trader_id: String,
    score: Float,
    trade_count: Int,
    avg_lead_time_ms: Int
  )
}

/// Detect insiders for a specific market by correlating trades with subsequent probability spikes.
pub fn detect_insiders(db: gleamdb.Db, market_id: String) -> List(AlphaScore) {
  // 1. Get all traders who have acted in this market
  let traders = get_market_traders(db, market_id)
  
  list.filter_map(traders, fn(trader_id) {
    // 2. Get this trader's ticks
    let trader_ticks = get_trader_ticks_for_market(db, trader_id, market_id)
    
    // 3. Score the trader based on lead-time to probability spikes
    // We fetch the full probability series for correlation
    case market.get_probability_series(db, market_id, "Yes") {
       Ok(full_series) -> {
         let score = calculate_alpha_score(trader_id, trader_ticks, full_series)
         // io.println("DEBUG: Trader " <> trader_id <> " score: " <> float.to_string(score.score))
         case score.trade_count > 0 {
           True -> Ok(score)
           False -> Error(Nil)
         }
       }
       _ -> Error(Nil)
    }
  })
}

fn get_market_traders(db: gleamdb.Db, market_id: String) -> List(String) {
  let query = [
    types.Positive(#(types.Var("t"), "tick/market", types.Val(fact.Ref(fact.EntityId(fact.phash2(market_id)))))),
    types.Positive(#(types.Var("t"), "tick/trader", types.Var("trader")))
  ]
  
  case gleamdb.query(db, query).rows {
    [] -> []
    rows -> {
      list.filter_map(rows, fn(row) {
        case dict.get(row, "trader") {
          Ok(fact.Str(id)) -> Ok(id)
          _ -> Error(Nil)
        }
      })
      |> list.unique()
    }
  }
}

fn get_trader_ticks_for_market(db: gleamdb.Db, trader_id: String, market_id: String) -> List(market.PredictionTick) {
  let query = [
    types.Positive(#(types.Var("t"), "tick/market", types.Val(fact.Ref(fact.EntityId(fact.phash2(market_id)))))),
    types.Positive(#(types.Var("t"), "tick/trader", types.Val(fact.Str(trader_id)))),
    types.Positive(#(types.Var("t"), "tick/probability", types.Var("prob"))),
    types.Positive(#(types.Var("t"), "tick/timestamp", types.Var("ts"))),
    types.Positive(#(types.Var("t"), "tick/volume", types.Var("vol"))),
    types.Positive(#(types.Var("t"), "tick/outcome", types.Var("out")))
  ]
  
  case gleamdb.query(db, query).rows {
    [] -> []
    rows -> {
      list.filter_map(rows, fn(row) {
        case dict.get(row, "prob"), dict.get(row, "ts"), dict.get(row, "vol"), dict.get(row, "out") {
          Ok(fact.Float(p)), Ok(fact.Int(t)), Ok(fact.Int(v)), Ok(fact.Str(o)) -> {
            Ok(market.PredictionTick(market_id, o, p, v, t, trader_id))
          }
          _, _, _, _ -> Error(Nil)
        }
      })
    }
  }
}

/// Calculate alpha score for a trader.
/// Higher score = trader buys consistently before probability increases.
fn calculate_alpha_score(
  trader_id: String,
  trader_ticks: List(market.PredictionTick),
  full_series: List(#(Int, Float))
) -> AlphaScore {
  let #(total_score, total_lead, count) = list.fold(trader_ticks, #(0.0, 0, 0), fn(acc, tick) {
    let #(sum_score, sum_lead, c) = acc
    
    // Find the max probability in the next 10 minutes (600s)
    let lookahead_window = 600
    let window_ticks = list.filter(full_series, fn(tp) {
      tp.0 > tick.timestamp && tp.0 <= tick.timestamp + lookahead_window
    })
    
    case window_ticks {
      [] -> acc
      _ -> {
        let max_prob = list.fold(window_ticks, 0.0, fn(m, tp) { float.max(m, tp.1) })
        let profit_potential = max_prob -. tick.probability
        
        // If they bought before a pump, record lead time
        case profit_potential >. 0.05 {
          True -> {
             // Find first time it hit at least 80% of max_prob in window
             let inflection = list.find(window_ticks, fn(tp) { tp.1 >=. tick.probability +. 0.8 *. profit_potential })
             let lead = case inflection {
               Ok(#(ts, _)) -> ts - tick.timestamp
               _ -> 0
             }
             #(sum_score +. profit_potential, sum_lead + lead, c + 1)
          }
          False -> #(sum_score, sum_lead, c + 1)
        }
      }
    }
  })
  
  let avg_lead = case count {
    0 -> 0
    _ -> total_lead / count
  }
  
  AlphaScore(trader_id, total_score, count, avg_lead)
}
