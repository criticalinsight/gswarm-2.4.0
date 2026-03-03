import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/option.{None}
import gleam/dict
import gleam/result
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/q
import gswarm/amka_domain


// --- Core Market Types ---



/// The kind of prediction market.
/// Binary = Yes/No (probability 0.0–1.0)
/// MultiOutcome = N outcomes, probabilities should sum to ~1.0
/// Scalar = Numeric range prediction (future)
pub type MarketType {
  Binary
  MultiOutcome
  Scalar
}

/// The lifecycle status of a prediction market.
/// Resolved carries the winning outcome for settlement.
pub type MarketStatus {
  Open
  Closed
  Resolved(winning_outcome: String)
}

/// A prediction market: a question with possible outcomes.
/// `source` tracks provenance (e.g. "manifold", "polymarket", "internal").
pub type Market {
  Market(
    id: String,
    question: String,
    outcomes: List(String),
    market_type: MarketType,
    status: MarketStatus,
    close_time: Int,
    source: String
  )
}

// --- Tick Types ---

/// Legacy tick: USD spot price for crypto feeds.
/// Preserved for backward compatibility with live_ticker, ticker, backtest.
pub type Tick {
  Tick(
    market_id: String,
    outcome: String,
    price: Float,
    volume: Int,
    timestamp: Int,
    trader_id: String
  )
}

/// Prediction market tick: probability in [0.0, 1.0] for a specific outcome.
/// This is the native representation for event-outcome markets.
pub type PredictionTick {
  PredictionTick(
    market_id: String,
    outcome: String,
    probability: Float,
    volume: Int,
    timestamp: Int,
    trader_id: String
  )
}

// --- Query Functions ---

/// Retrieve the latest 50D Alpha vector for a market from GleamDB.
/// Queries the `market/latest_vector` attribute written by `ingest_tick_with_vector`.
pub fn get_latest_vector(db: gleamdb.Db, market_id: String) -> Result(List(Float), Nil) {
  let query = [
    types.Positive(#(types.Var("m"), "market/id", types.Val(fact.Str(market_id)))),
    types.Positive(#(types.Var("m"), "market/latest_vector", types.Var("vec")))
  ]
  case gleamdb.query(db, query).rows {
    [row, ..] -> case dict.get(row, "vec") {
      Ok(fact.Vec(v)) -> Ok(v)
      _ -> Error(Nil)
    }
    _ -> Error(Nil)
  }
}

// --- Prediction Tick Functions ---

/// Validate a prediction tick: probability must be in [0.0, 1.0], volume >= 0.
pub fn validate_prediction_tick(tick: PredictionTick) -> Result(Nil, String) {
  case tick.probability <. 0.0 || tick.probability >. 1.0 {
    True -> Error("Probability out of bounds [0.0, 1.0]: " <> float.to_string(tick.probability))
    False -> {
      case tick.volume < 0 {
        True -> Error("Negative volume: " <> int.to_string(tick.volume))
        False -> Ok(Nil)
      }
    }
  }
}

/// Convert a PredictionTick to a basic vector: [probability, volume_normalized].
/// Full Alpha enrichment happens in market_feed via analytics.
pub fn prediction_tick_to_vector(tick: PredictionTick) -> List(Float) {
  [
    tick.probability,
    int.to_float(tick.volume) /. 10_000.0
  ]
}

/// Ingest a prediction tick with its computed Alpha vector.
/// Stores probability (not price) as the primary fact.
pub fn ingest_prediction_tick(
  db: gleamdb.Db,
  tick: PredictionTick,
  vector: List(Float)
) -> Result(types.DbState, String) {
  use _ <- result.try(validate_prediction_tick(tick))

  let market_ref = fact.Ref(fact.EntityId(fact.phash2(tick.market_id)))
  
  // Deterministic Tick ID (Native Identity Sovereignty)
  let tick_entity = fact.deterministic_uid(#(tick.market_id, tick.timestamp, tick.outcome))

  let facts = [
    #(tick_entity, "tick/market", market_ref),
    #(tick_entity, "tick/outcome", fact.Str(tick.outcome)),
    #(tick_entity, "tick/probability", fact.Float(tick.probability)),
    #(tick_entity, "tick/price/" <> tick.outcome, fact.Float(tick.probability)),
    #(tick_entity, "tick/volume", fact.Int(tick.volume)),
    #(tick_entity, "tick/timestamp", fact.Int(tick.timestamp)),
    #(tick_entity, "tick/trader", fact.Str(tick.trader_id)),
    #(tick_entity, "tick/vector", fact.Vec(vector)),
    
    // Update market context so Analyst can see the latest state
    #(fact.deterministic_uid(tick.market_id), "market/latest_vector", fact.Vec(vector))
  ]

  gleamdb.transact(db, facts)
}

/// Ingest a batch of ticks with their Alpha vectors.
/// Optimized for Phase 39 High-Throughput (10k/sec).
pub fn ingest_batch_with_vectors(
  db: gleamdb.Db,
  ticks: List(#(PredictionTick, List(Float)))
) -> Result(types.DbState, String) {
  let facts = list.flat_map(ticks, fn(pair) {
    let #(tick, vector) = pair
    let market_ref = fact.Ref(fact.EntityId(fact.phash2(tick.market_id)))
    let tick_entity = fact.deterministic_uid(#(tick.market_id, tick.timestamp, tick.outcome))

    [
      #(tick_entity, "tick/market", market_ref),
      #(tick_entity, "tick/outcome", fact.Str(tick.outcome)),
      #(tick_entity, "tick/probability", fact.Float(tick.probability)),
      #(tick_entity, "tick/volume", fact.Int(tick.volume)),
      #(tick_entity, "tick/timestamp", fact.Int(tick.timestamp)),
      #(tick_entity, "tick/trader", fact.Str(tick.trader_id)),
      #(tick_entity, "tick/vector", fact.Vec(vector)),
      #(fact.deterministic_uid(tick.market_id), "market/latest_vector", fact.Vec(vector))
    ]
  })

  gleamdb.transact(db, facts)
}

// --- Legacy Tick Functions (Crypto Spot Feed) ---

pub fn tick_to_vector(tick: Tick) -> List(Float) {
  [
    tick.price /. 1000.0,
    0.5, 
    int.to_float(tick.volume) /. 10000.0
  ]
}

pub fn validate_tick(tick: Tick) -> Result(Nil, String) {
  case tick.price <. 0.0 {
    True -> Error("Negative price detected: " <> float.to_string(tick.price))
    False -> {
      case tick.volume < 0 {
        True -> Error("Negative volume detected: " <> int.to_string(tick.volume))
        False -> Ok(Nil)
      }
    }
  }
}

pub fn ingest_tick(db: gleamdb.Db, tick: Tick) -> Result(types.DbState, String) {
  ingest_tick_with_vector(db, tick, tick_to_vector(tick))
}

pub fn ingest_batch(db: gleamdb.Db, ticks: List(Tick)) -> Result(types.DbState, String) {
  use _ <- result.try(list.try_each(ticks, validate_tick))
  
  let facts = list.flat_map(ticks, fn(tick) {
    let vector = tick_to_vector(tick)
    [
      #(fact.Lookup(#("market/id", fact.Str(tick.market_id))), "tick/price/" <> tick.outcome, fact.Float(tick.price)),
      #(fact.Lookup(#("market/id", fact.Str(tick.market_id))), "tick/volume/" <> tick.outcome, fact.Int(tick.volume)),
      #(fact.Lookup(#("market/id", fact.Str(tick.market_id))), "tick/timestamp", fact.Int(tick.timestamp)),
      #(fact.Lookup(#("market/id", fact.Str(tick.market_id))), "tick/trader", fact.Str(tick.trader_id)),
      #(fact.Lookup(#("market/id", fact.Str(tick.market_id))), "tick/vector", fact.Vec(vector))
    ]
  })
  
  gleamdb.transact(db, facts)
}

pub fn ingest_tick_with_vector(db: gleamdb.Db, tick: Tick, vector: List(Float)) -> Result(types.DbState, String) {
  let tick_eid = fact.event_uid("tick", tick.timestamp)
  let assert fact.Uid(tick_id) = tick_eid
  let market_eid = fact.Lookup(#("market/id", fact.Str(tick.market_id)))
  
  let facts = [
    #(market_eid, "market/ticks", fact.Ref(tick_id)),
    #(tick_eid, "tick/market_id", fact.Str(tick.market_id)),
    #(tick_eid, "tick/price/" <> tick.outcome, fact.Float(tick.price)),
    #(tick_eid, "tick/volume/" <> tick.outcome, fact.Int(tick.volume)),
    #(tick_eid, "tick/timestamp", fact.Int(tick.timestamp)),
    #(tick_eid, "tick/trader", fact.Str(tick.trader_id)),
    #(tick_eid, "tick/vector", fact.Vec(vector)),
    #(tick_eid, "market/latest_vector", fact.Vec(vector))
  ]
  
  gleamdb.transact(db, facts)
}

// --- Schema & Market Creation ---

pub fn configure_tick_retention(db: gleamdb.Db) {
  let config = fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None)
  let component_config = fact.AttributeConfig(unique: False, component: True, retention: fact.All, cardinality: fact.Many, check: None)
  let unique_config = fact.AttributeConfig(unique: True, component: False, retention: fact.All, cardinality: fact.Many, check: None)
  
  // Market ID must be unique
  let _ = gleamdb.set_schema(db, "market/id", unique_config)
  let _ = gleamdb.set_schema(db, "market/ticks", component_config)
  // Internal UID for Lookup mechanism (workaround for indexing issue)
  let _ = gleamdb.set_schema(db, "market/uid", unique_config)
  
  let _ = gleamdb.set_schema(db, "tick/market_id", config)
  let _ = gleamdb.set_schema(db, "tick/market", config)
  let _ = gleamdb.set_schema(db, "tick/price/Yes", config)
  let _ = gleamdb.set_schema(db, "tick/probability/YES", config)
  let _ = gleamdb.set_schema(db, "tick/probability/NO", config)
  let _ = gleamdb.set_schema(db, "tick/volume/Yes", config)
  let _ = gleamdb.set_schema(db, "tick/timestamp", config)
  let _ = gleamdb.set_schema(db, "tick/trader", config)
  let _ = gleamdb.set_schema(db, "tick/vector", config)
  
  // Trade Activity Schemas (Phase 7)
  let _ = gleamdb.set_schema(db, "trade/market_id", config)
  let _ = gleamdb.set_schema(db, "trade/user", config)
  let _ = gleamdb.set_schema(db, "trade/timestamp", config)
  let _ = gleamdb.set_schema(db, "trade/price", config)
  Nil
}

/// Record a trade activity event for future "First-Mover" analysis.
pub fn record_trade_activity(db: gleamdb.Db, trade: amka_domain.TradeActivity) -> Result(types.DbState, String) {
  let uid = fact.deterministic_uid(#(trade.market_slug, trade.user, trade.timestamp))
  let facts = [
    #(uid, "trade/market_id", fact.Str(trade.market_slug)),
    #(uid, "trade/user", fact.Str(trade.user)),
    #(uid, "trade/timestamp", fact.Int(trade.timestamp)),
    #(uid, "trade/price", fact.Float(trade.price))
  ]
  gleamdb.transact(db, facts)
}

/// Retrieve trades for a market within a time window.
pub fn get_trades_in_window(db: gleamdb.Db, market_id: String, start_ts: Int, end_ts: Int) -> List(amka_domain.TradeActivity) {
  let query = [
    types.Positive(#(types.Var("t"), "trade/market_id", types.Val(fact.Str(market_id)))),
    types.Positive(#(types.Var("t"), "trade/user", types.Var("user"))),
    types.Positive(#(types.Var("t"), "trade/timestamp", types.Var("ts"))),
    types.Positive(#(types.Var("t"), "trade/price", types.Var("price"))),
    types.Filter(types.And(
      types.Gt(types.Var("ts"), types.Val(fact.Int(start_ts - 1))),
      types.Lt(types.Var("ts"), types.Val(fact.Int(end_ts + 1)))
    ))
  ]
  
  case gleamdb.query(db, query).rows {
    [] -> []
    rows -> list.filter_map(rows, fn(row) {
      case dict.get(row, "user"), dict.get(row, "ts"), dict.get(row, "price") {
        Ok(fact.Str(u)), Ok(fact.Int(ts)), Ok(fact.Float(p)) -> {
          Ok(amka_domain.TradeActivity(
            user: u,
            market_title: "",
            market_slug: market_id,
            trade_type: amka_domain.Buy, // Assumption for detection
            size: 0.0,
            price: p,
            usdc_size: 0.0,
            timestamp: ts
          ))
        }
        _, _, _ -> Error(Nil)
      }
    })
  }
}

/// Create a prediction market in GleamDB.
/// Stores market metadata including type, status, close time, and source.
pub fn create_prediction_market(db: gleamdb.Db, m: Market) -> Result(types.DbState, String) {
  let type_str = case m.market_type {
    Binary -> "binary"
    MultiOutcome -> "multi"
    Scalar -> "scalar"
  }
  let status_str = case m.status {
    Open -> "open"
    Closed -> "closed"
    Resolved(w) -> "resolved:" <> w
  }
  // Use deterministic ID hash to bypass Lookup indexing bug (Phase 23 fix)
  let uid = fact.deterministic_uid(m.id)
  
  let facts = [
    #(uid, "market/id", fact.Str(m.id)),
    #(uid, "market/type", fact.Str(type_str)),
    #(uid, "market/status", fact.Str(status_str)),
    #(uid, "market/close_time", fact.Int(m.close_time)),
    #(uid, "market/source", fact.Str(m.source)),
    #(uid, "market/question", fact.Str(m.question))
  ]

  gleamdb.transact(db, facts)
}

/// Legacy: create a simple market (backward compat for tests and crypto).
pub fn create_market(db: gleamdb.Db, market: Market) -> Result(types.DbState, String) {
  let uid = fact.deterministic_uid(market.id)
  let facts = [
    #(uid, "market/id", fact.Str(market.id)),
    #(uid, "market/question", fact.Str(market.question))
  ]
  
  gleamdb.transact_with_timeout(db, facts, 10000)
}

// --- Cross-Market Analysis Helpers ---

/// Retrieve all active prediction markets (status = "open").
pub fn get_active_prediction_markets(db: gleamdb.Db) -> Result(List(String), Nil) {
  let query = [
    types.Positive(#(types.Var("m"), "market/status", types.Val(fact.Str("open")))),
    types.Positive(#(types.Var("m"), "market/id", types.Var("id")))
  ]
  
  case gleamdb.query(db, query).rows {
    [] -> Ok([])
    rows -> {
      let ids = list.filter_map(rows, fn(row) {
        case dict.get(row, "id") {
          Ok(fact.Str(id)) -> Ok(id)
          _ -> Error(Nil)
        }
      })
      Ok(ids)
    }
  } 
}

/// Retrieve the probability time series for a market's outcome.
/// Returns a list of #(timestamp, probability) sorted by time ascending.
/// Note: Inefficiently pulls all ticks and sorts in memory due to DB limitations.
pub fn get_probability_series(
  db: gleamdb.Db, 
  market_id: String, 
  outcome: String
) -> Result(List(#(Int, Float)), Nil) {
  let query = 
    q.new()
    |> q.where(types.Var("t"), "tick/market", types.Val(fact.Ref(fact.EntityId(fact.phash2(market_id)))))
    |> q.where(types.Var("t"), "tick/outcome", types.Val(fact.Str(outcome)))
    |> q.where(types.Var("t"), "tick/probability", types.Var("prob"))
    |> q.where(types.Var("t"), "tick/timestamp", types.Var("ts"))
    // Database-native sort (Phase 23)
    |> q.order_by("ts", types.Asc)
    |> q.to_clauses

  case gleamdb.query(db, query).rows {
    [] -> Ok([])
    rows -> {
      let series = list.filter_map(rows, fn(row) {
        case dict.get(row, "ts"), dict.get(row, "prob") {
          Ok(fact.Int(t)), Ok(fact.Float(p)) -> Ok(#(t, p))
          _, _ -> Error(Nil)
        }
      })
      // No manual sort needed!
      io.println("📊 Series for " <> market_id <> ": " <> int.to_string(list.length(series)) <> " items")
      Ok(series)
    }
  }
}

/// Retrieve the probability time series for a market's outcome since a specific timestamp.
/// Returns a list of #(timestamp, probability) sorted by time ascending.
/// Optimized for Phase 49 lead-time analysis.
pub fn get_probability_series_since(
  db: gleamdb.Db,
  market_id: String,
  outcome: String,
  since: Int
) -> Result(List(#(Int, Float)), Nil) {
  let query = 
    q.new()
    |> q.where(types.Var("t"), "tick/market", types.Val(fact.Ref(fact.EntityId(fact.phash2(market_id)))))
    |> q.where(types.Var("t"), "tick/outcome", types.Val(fact.Str(outcome)))
    |> q.where(types.Var("t"), "tick/probability", types.Var("prob"))
    |> q.where(types.Var("t"), "tick/timestamp", types.Var("ts"))
    // Optimized: Use native since helper from backported core
    |> q.since("ts", q.i(since))
    |> q.order_by("ts", types.Asc)
    |> q.to_clauses

  case gleamdb.query(db, query).rows {
    [] -> Ok([])
    rows -> {
      let series = list.filter_map(rows, fn(row) {
        case dict.get(row, "ts"), dict.get(row, "prob") {
          Ok(fact.Int(t)), Ok(fact.Float(p)) -> Ok(#(t, p))
          _, _ -> Error(Nil)
        }
      })
      io.println("📊 Optimized Series for " <> market_id <> " since " <> int.to_string(since) <> ": " <> int.to_string(list.length(series)) <> " items")
      Ok(series)
    }
  }
}


// --- Search Functions (GleamDB v2.1.0) ---

/// Search for markets where the ID starts with the given prefix.
/// Uses the efficient ART index (Phase 45) for O(k) lookups.
pub fn search_markets(db: gleamdb.Db, prefix: String) -> Result(List(Market), Nil) {
  let query = [
    types.StartsWith("id", prefix),
    types.Positive(#(types.Var("m"), "market/id", types.Var("id"))),
    types.Positive(#(types.Var("m"), "market/question", types.Var("q"))),
    types.Positive(#(types.Var("m"), "market/status", types.Var("s")))
  ]
  
  case gleamdb.query(db, query).rows {
    [] -> Ok([])
    rows -> {
      let markets = list.filter_map(rows, fn(row) {
        case dict.get(row, "id"), dict.get(row, "q"), dict.get(row, "s") {
          Ok(fact.Str(id)), Ok(fact.Str(q)), Ok(fact.Str(s)) -> {
             // For now, reconstruct a partial Market object or minimal view
             // In a real app, we might pull the full object or just return metadata
             let status = case s {
               "open" -> Open
               "closed" -> Closed
               "resolved:" <> w -> Resolved(w)
               _ -> Open
             }
             Ok(Market(
               id: id, 
               question: q, 
               outcomes: [], // Not fetched for shallow search
               market_type: Binary, // Default/Placeholder
               status: status,
               close_time: 0,
               source: "search"
             ))
          }
          _, _, _ -> Error(Nil)
        }
      })
      Ok(markets)
    }
  }
}

/// Find markets with similar Alpha vectors to the given market.
/// Uses the HNSW index (Phase 44) for semantic similarity.
pub fn find_similar_markets(db: gleamdb.Db, market_id: String, limit: Int, threshold: Float) -> Result(List(Market), Nil) {
  // 1. Get the target market's vector
  use vector <- result.try(get_latest_vector(db, market_id))
  
  // 2. Query for similar markets using HNSW
  let query = [
    // "m" is the market entity UID
    // "vec" is the vector value
    types.Similarity("vec", vector, threshold), 
    types.Limit(limit),
    types.Positive(#(types.Var("m"), "market/latest_vector", types.Var("vec"))),
    types.Positive(#(types.Var("m"), "market/id", types.Var("id"))),
    types.Positive(#(types.Var("m"), "market/question", types.Var("q")))
  ]
  
  case gleamdb.query(db, query).rows {
    [] -> Ok([])
    rows -> {
      let markets = list.filter_map(rows, fn(row) {
        case dict.get(row, "id"), dict.get(row, "q") {
          Ok(fact.Str(id)), Ok(fact.Str(q)) -> {
             // Exclude self from results if needed (though Similarity might return it with dist 0)
             case id == market_id {
               True -> Error(Nil)
               False -> Ok(Market(
                 id: id, 
                 question: q, 
                 outcomes: [], 
                 market_type: Binary, 
                 status: Open, 
                 close_time: 0, 
                 source: "similarity"
               ))
             }
          }
          _, _ -> Error(Nil)
        }
      })
      Ok(markets)
    }
  }
}
