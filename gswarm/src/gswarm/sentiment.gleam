import gleam/string
import gleam/list
import gleam/float
import gleam/int

pub type Sentiment {
  Bullish
  Bearish
  Neutral
}

const bullish_keywords = [
  "surge", "rally", "buy", "gain", "profit", "growth", "high", "success",
  "approved", "partnership", "launch", "bull", "moon", "pumping", "listing",
  "breakout", "ath", "positive", "win", "expansion"
]

const bearish_keywords = [
  "drop", "crash", "sell", "loss", "decline", "low", "fail", "rejected",
  "bankrupt", "scam", "bear", "dumping", "delisted", "breakdown", "negative",
  "loss", "lawsuit", "hack", "drain", "halt"
]

/// Heuristic sentiment scorer based on keyword presence.
/// Returns a score between -1.0 (Extreme Bearish) and 1.0 (Extreme Bullish).
pub fn score(text: String) -> Float {
  let lower_text = string.lowercase(text)
  
  let bull_hits = list.filter(bullish_keywords, fn(k) { string.contains(lower_text, k) }) |> list.length
  let bear_hits = list.filter(bearish_keywords, fn(k) { string.contains(lower_text, k) }) |> list.length
  
  let total = bull_hits + bear_hits
  case total {
    0 -> 0.0
    _ -> {
      let score = int_to_float(bull_hits - bear_hits) /. int_to_float(total)
      // Dampen by volume of keywords to avoid extreme scores on single words
      let confidence = float.min(1.0, int_to_float(total) /. 3.0)
      score *. confidence
    }
  }
}

pub fn to_label(score: Float) -> Sentiment {
  case score {
    s if s >. 0.2 -> Bullish
    s if s <. -0.2 -> Bearish
    _ -> Neutral
  }
}

fn int_to_float(i: Int) -> Float {
  int.to_float(i)
}
