import gleam/io
import gleam/float
import gswarm/sentiment

pub fn main() {
  io.println("🧪 Gswarm: Verifying Phase 49 Sentiment Analysis...")
  
  let scenarios = [
    #("BTC price surge as institutional adoption growing rapidly", "Bullish"),
    #("Market crash follows massive hack on decentralized exchange", "Bearish"),
    #("Developers announce new partnership and future growth plans", "Bullish"),
    #("SEC rejects latest ETF application, decline expected", "Bearish"),
    #("Standard market sideways movement with neutral sentiment", "Neutral")
  ]
  
  list.each(scenarios, fn(scenario) {
    let #(text, expected_label) = scenario
    let score = sentiment.score(text)
    let label = sentiment.to_label(score)
    let outcome = case string.inspect(label) == expected_label {
      True -> "✅ PASS"
      False -> "❌ FAIL"
    }
    
    io.println("Headline: [" <> text <> "]")
    io.println("  Score: " <> float.to_string(score))
    io.println("  Label: " <> string.inspect(label) <> " (Expected: " <> expected_label <> ")")
    io.println("  Result: " <> outcome)
    io.println("")
  })
}

import gleam/list
import gleam/string
