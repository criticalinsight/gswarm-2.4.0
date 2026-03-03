import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/dict
import gleam/erlang/process
import gleamdb
import gleamdb/fact
import gleamdb/shared/types

// The Correlator: Cross-correlates News Sentiment with Price Movement.
// Stores derived "correlation facts" — immutable values, not mutations (Hickey).
//
// Signal = f(news_vector, price_delta)
// A positive signal means news preceded an UP move; negative means DOWN.

pub type CorrelationResult {
  CorrelationResult(
    news_id: String,
    direction: String,
    delta_pct: Float,
    signal_score: Float
  )
}

pub fn start_correlator(db: gleamdb.Db) {
  process.spawn_unlinked(fn() {
    io.println("📊 Correlator: Started. Scanning for news→price signals...")
    loop(db)
  })
}

fn loop(db: gleamdb.Db) {
  process.sleep(30_000) // Correlate every 30s

  // 1. Query recent news vectors
  let news_query = [
    types.Positive(#(types.Var("n"), "news/title", types.Var("title"))),
    types.Positive(#(types.Var("n"), "news/sentiment", types.Var("sent"))),
    types.Positive(#(types.Var("n"), "news/timestamp", types.Var("nts")))
  ]
  let news_results = gleamdb.query(db, news_query)

  // 2. Query current BTC price vector
  let price_query = [
    types.Positive(#(types.Val(fact.Str("m_btc")), "market/id", types.Var("m"))),
    types.Positive(#(types.Var("m"), "tick/price/Yes", types.Var("price"))),
    types.Positive(#(types.Var("m"), "tick/vector", types.Var("pvec")))
  ]
  let price_results = gleamdb.query(db, price_query)

  // 3. Compute correlation signal
  let news_count = list.length(news_results.rows)
  let price_count = list.length(price_results.rows)

  case news_count > 0, price_count > 0 {
    True, True -> {
      // Extract the latest price for signal computation
      let current_price = extract_latest_price(price_results)
      let avg_sentiment = compute_avg_sentiment(news_results)

      // Signal Score = sentiment_magnitude × price_momentum_direction
      // Positive = bullish news + upward price = strong BUY signal
      // Negative = bearish news + downward price = strong SELL signal
      let signal_score = avg_sentiment *. current_price

      // Store the correlation fact
      let corr_id = "corr_" <> int.to_string(erlang_system_time())
      let lookup = fact.Lookup(#("correlation/id", fact.Str(corr_id)))
      let correlation_facts = [
        #(lookup, "correlation/id", fact.Str(corr_id)),
        #(lookup, "correlation/signal_score", fact.Float(signal_score)),
        #(lookup, "correlation/news_count", fact.Int(news_count)),
        #(lookup, "correlation/price_at_signal", fact.Float(current_price)),
        #(lookup, "correlation/sentiment_avg", fact.Float(avg_sentiment)),
        #(lookup, "correlation/timestamp", fact.Int(erlang_system_time()))
      ]
      let _ = gleamdb.transact(db, correlation_facts)

      let direction = case signal_score >. 0.0 {
        True -> "BULLISH 🟢"
        False -> "BEARISH 🔴"
      }

      io.println("📊 Correlator: " <> direction
        <> " | Signal: " <> float.to_string(signal_score)
        <> " | News: " <> int.to_string(news_count)
        <> " | Sentiment: " <> float.to_string(avg_sentiment)
        <> " | Price: $" <> float.to_string(current_price))
    }
    _, _ -> {
      io.println("📊 Correlator: Waiting for data (News: " <> int.to_string(news_count)
        <> ", Prices: " <> int.to_string(price_count) <> ")")
    }
  }

  loop(db)
}

/// Detects traders who move before news spikes.
/// Hickey Principle: Value is in the nexus of events.
pub fn detect_insider_patterns(db: gleamdb.Db) -> List(String) {
  // Query 1: Find all (Trader, TradeTS, Market)
  let trades_query = [
    types.Positive(#(types.Var("t"), "tick/trader", types.Var("trader"))),
    types.Positive(#(types.Var("t"), "tick/timestamp", types.Var("trade_ts"))),
    types.Positive(#(types.Var("t"), "tick/market", types.Var("market")))
  ]
  let trades = gleamdb.query(db, trades_query).rows

  // Query 2: Find all (NewsTitle, NewsTS)
  let news_query = [
    types.Positive(#(types.Var("n"), "news/title", types.Var("title"))),
    types.Positive(#(types.Var("n"), "news/timestamp", types.Var("news_ts")))
  ]
  let news = gleamdb.query(db, news_query).rows

  // Manual Nexus Join (Datalog doesn't yet support cross-join inequality in 1 query)
  let insiders = list.filter_map(trades, fn(trade_row) {
    case dict.get(trade_row, "trader"), dict.get(trade_row, "trade_ts") {
      Ok(fact.Str(trader)), Ok(fact.Int(tts)) -> {
        let leads = list.filter(news, fn(news_row) {
          case dict.get(news_row, "news_ts") {
            Ok(fact.Int(nts)) -> {
              // Lead-time: News published 0-15m AFTER trade
              nts > tts && nts <= tts + 900
            }
            _ -> False
          }
        })
        
        case leads != [] {
          True -> Ok(trader)
          False -> Error(Nil)
        }
      }
      _, _ -> Error(Nil)
    }
  })

  // Group and count suspicious hits
  insiders 
  |> list.group(fn(x) { x })
  |> dict.to_list()
  |> list.filter(fn(p) { list.length(p.1) >= 3 }) // Requirement: At least 3 patterns
  |> list.map(fn(p) { p.0 })
}

/// Extract the most recent price from query results
fn extract_latest_price(results: types.QueryResult) -> Float {
  case list.first(results.rows) {
    Ok(row) -> {
      case dict.get(row, "price") {
        Ok(fact.Float(p)) -> p
        _ -> 0.0
      }
    }
    _ -> 0.0
  }
}

/// Compute average sentiment from news vectors
/// Uses the first component of the news vector as a proxy for sentiment magnitude
fn compute_avg_sentiment(results: types.QueryResult) -> Float {
  let sentiments = list.filter_map(results.rows, fn(row) {
    case dict.get(row, "sent") {
      Ok(fact.Float(s)) -> Ok(s)
      _ -> Error(Nil)
    }
  })

  let count = list.length(sentiments)
  case count > 0 {
    True -> {
      let sum = list.fold(sentiments, 0.0, fn(acc, s) { acc +. s })
      sum /. int.to_float(count)
    }
    False -> 0.0
  }
}

@external(erlang, "erlang", "system_time")
fn do_system_time(unit: Int) -> Int

fn erlang_system_time() -> Int {
  do_system_time(1000)
}
