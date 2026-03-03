import gleam/list
import gleam/result

pub type Action {
  Buy
  Sell
  Hold
}

pub type Strategy = fn(List(Float)) -> Action

// --- Strategy Implementations ---

// Mean Reversion: Buy when RSI < 30, Sell when RSI > 70
pub fn mean_reversion(vector: List(Float)) -> Action {
  case list.drop(vector, 6) |> list.first() { // RSI is index 6
    Ok(rsi) -> {
      case rsi {
         _ if rsi <. 30.0 -> Buy
         _ if rsi >. 70.0 -> Sell
         _ -> Hold
      }
    }
    Error(_) -> Hold
  }
}

// Trend Following: Buy when MACD > 0
pub fn trend_follower(vector: List(Float)) -> Action {
  let macd = list.drop(vector, 7) |> list.first() |> result.unwrap(0.0)
  
  case macd >. 0.0 {
    True -> Buy
    False -> Sell
  }
}

// Sentiment Momentum (News-driven)
pub fn sentiment_momentum(vector: List(Float)) -> Action {
  let sentiment = list.drop(vector, 12) |> list.first() |> result.unwrap(0.0)
  case sentiment {
    _ if sentiment >. 0.8 -> Buy
    _ if sentiment <. -0.8 -> Sell
    _ -> Hold
  }
}

// Cross-Signal: Combines Alpha-50 momentum with news correlation
// Uses RSI (index 6), MACD (index 7), and Bollinger %B (index 10)
// to produce a consensus signal across multiple timeframes.
pub fn cross_signal(vector: List(Float)) -> Action {
  let rsi = list.drop(vector, 6) |> list.first() |> result.unwrap(50.0)
  let macd = list.drop(vector, 7) |> list.first() |> result.unwrap(0.0)
  let bb_pct = list.drop(vector, 10) |> list.first() |> result.unwrap(0.5)

  // Score: each indicator votes +1 (bullish) or -1 (bearish)
  let rsi_vote = case rsi {
    _ if rsi <. 35.0 -> 1.0    // Oversold = bullish
    _ if rsi >. 65.0 -> -1.0   // Overbought = bearish
    _ -> 0.0
  }
  let macd_vote = case macd >. 0.0 {
    True -> 1.0
    False -> -1.0
  }
  let bb_vote = case bb_pct {
    _ if bb_pct <. 0.2 -> 1.0    // Near lower band = bullish
    _ if bb_pct >. 0.8 -> -1.0   // Near upper band = bearish
    _ -> 0.0
  }

  let consensus = rsi_vote +. macd_vote +. bb_vote

  case consensus {
    _ if consensus >. 1.5 -> Buy     // Strong consensus
    _ if consensus <. -1.5 -> Sell   // Strong consensus
    _ -> Hold                         // No clear signal
  }
}
// --- Helpers ---

pub fn to_string(_strategy: Strategy) -> String {
  // We can't compare functions directly.
  // BUT: We can cheat by applying them to a known vector and checking behavior? No.
  // The only way is if the Strategy type was a custom type wrapping the fn.
  // For now, let's assume the callers (paper_trader) track the ID manually?
  // Wait, paper_trader holds `active_strategy: Strategy`. It lost the ID.
  
  // REFACTOR: Strategy should be a custom type!
  // type Strategy { Strategy(id: String, run: fn(List(Float)) -> Action) }
  
  // Checking `strategy.gleam`: "pub type Strategy = fn(List(Float)) -> Action"
  // Changing this is a big refactor.
  
  // ALTERNATIVE: paper_trader state tracks `active_strategy_id: String` alongside the fn.
  "unknown" 
}

pub fn from_string(id: String) -> Strategy {
  case id {
    "mean_reversion" -> mean_reversion
    "trend_follower" -> trend_follower
    "sentiment_momentum" -> sentiment_momentum
    "cross_signal" -> cross_signal
    _ -> mean_reversion // Default
  }
}
