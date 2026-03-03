import gswarm/amka_domain.{type TradeActivity, Buy, Sell}
import gswarm/market.{type Tick}
import gleam/option.{type Option, None, Some}
import gleam/list
import gleam/float
import gleam/int
import gleam/result

// The minimum probability shift required to consider it a "signal" (5%)
const signal_threshold = 0.05

// The maximum window to look ahead for a signal (1 hour in seconds)
const max_lookahead_seconds = 3600

// A calculated lag between a trade and a signal.
// negative = trade happened BEFORE signal (Insider!)
// positive = trade happened AFTER signal (Follower)
pub type Lag {
  Lag(
    minutes: Float,
    is_insider: Bool
  )
}

/// Compute the lead-time lag for a trade against a stream of future ticks.
/// Returns Some(Lag) if a significant inflection is found within the window.
pub fn compute_lag(trade: TradeActivity, future_ticks: List(Tick)) -> Option(Lag) {
  // 1. Filter ticks that occurred after the trade (or slightly before for context)
  // We only care about ticks *after* the trade to see if the trade *predicted* the move.
  // Actually, we need to find the *start* of the move.
  
  // Simple heuristic: Find the first tick where probability shifts by > 5% 
  // in the direction of the trade relative to the trade price.
  
  let target_direction = case trade.trade_type {
    Buy -> 1.0
    Sell -> -1.0
    _ -> 0.0
  }
  
  case target_direction {
    0.0 -> None // Redeems don't predict price moves
    dir -> find_inflection(trade, future_ticks, dir)
  }
}

fn find_inflection(
  trade: TradeActivity, 
  ticks: List(Tick), 
  direction: Float
) -> Option(Lag) {
  // Sort ticks by time just in case (though they should be time-ordered from DB)
  // We'll assume they are ordered for O(N).
  
  let entry_price = trade.price
  let entry_time = trade.timestamp
  
  // Find the first tick where (price - entry_price) * direction > threshold
  let inflection_tick = list.find(ticks, fn(t) {
    let delta = t.price -. entry_price
    let relative_move = delta *. direction
    
    // Check if move exceeds threshold AND is within lookahead window
    relative_move >. signal_threshold && { t.timestamp - entry_time } <= max_lookahead_seconds
  })
  
  case inflection_tick {
    Ok(t) -> {
      // Calculate lag in minutes
      // If t.timestamp > entry_time, lag is negative (Trade led the tick? No wait.)
      // Definition from PRD: "Negative Lag (Trade before Tick) is the signal we want."
      // So Lag = trade_time - inflection_time
      
      let lag_seconds = trade.timestamp - t.timestamp
      let lag_minutes = create_lag(lag_seconds)
      Some(lag_minutes)
    }
    Error(_) -> None
  }
}

fn create_lag(seconds: Int) -> Lag {
  let minutes = int.to_float(seconds) /. 60.0
  Lag(
    minutes: minutes,
    // Insider if trade happened BEFORE inflection (lag is negative)
    // Wait, if trade is at T=100 and inflection is T=105...
    // Lag = 100 - 105 = -5.
    // Yes, negative lag means trade was EARLY.
    is_insider: minutes <. 0.0
  )
}

/// Calculate the "Confidence Score" for a set of lags.
/// More consistent negative lags = higher confidence.
pub fn calculate_confidence(lags: List(Float)) -> Float {
  let count = list.length(lags)
  case count {
    0 -> 0.0
    _ -> {
      let insider_trades = list.filter(lags, fn(l) { l <. -1.0 }) // At least 1 min early
      let insider_count = list.length(insider_trades)
      
      // Simple ratio: (Insider Trades / Total Trades) * Log(Total Trades)
      // Log factor rewards consistency over sample size
      let ratio = int.to_float(insider_count) /. int.to_float(count)
      let weight = float.logarithm(int.to_float(count) +. 1.0) |> result.unwrap(1.0)
      
      // Clamp to 0.0 - 1.0 (approximated normalization)
      float.min(1.0, ratio *. { weight /. 3.0 }) 
    }
  }
}
/// Check if a trade is the "First-Mover" in a cluster of trades.
/// Returns True if the given trade has the absolute minimum timestamp among competing trades.
pub fn is_first_mover(trade: TradeActivity, others: List(TradeActivity)) -> Bool {
  let entries = [trade, ..others]
  let min_ts = list.fold(entries, trade.timestamp, fn(acc, t) {
    int.min(acc, t.timestamp)
  })
  trade.timestamp == min_ts
}
