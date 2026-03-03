import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/http/request
import gleam/hackney

// ... (existing imports)

// ... (existing code)

import gleam/json
import gleam/dynamic/decode
import gleam/result
import gleam/erlang/process
import gswarm/market
import gswarm/analytics
import gswarm/paper_trader
import gswarm/ingest_batcher
import gswarm/notifier
import gswarm/types
import gswarm/analyst
import gleam/option.{type Option, None, Some}
import gleam/string

/// A decoded Manifold Markets API response.
pub type ManifoldMarket {
  ManifoldMarket(
    id: String,
    question: String,
    probability: Float,
    volume: Float,
    close_time: Int,
    is_resolved: Bool,
    resolution: String
  )
}

/// Start prediction market feeds for a list of Manifold market slugs.
/// Each market gets its own polling loop (15s interval).
pub fn start_market_feed(
  batcher: process.Subject(ingest_batcher.Message),
  market_ids: List(String),
  trader: Option(process.Subject(paper_trader.Message)),
  notifier_actor: process.Subject(notifier.Message)
) {
  list.each(market_ids, fn(mid) {
    process.spawn_unlinked(fn() {
      io.println("🎲 MarketFeed: Tracking prediction market [" <> mid <> "]")
      loop(batcher, mid, [], trader, notifier_actor)
    })
  })
}

/// Main polling loop: fetch probability, compute Alpha, ingest, broadcast.
fn loop(
  batcher: process.Subject(ingest_batcher.Message),
  market_id: String,
  history: List(Float),
  trader: Option(process.Subject(paper_trader.Message)),
  notifier_actor: process.Subject(notifier.Message)
) {
  let ts = erlang_system_time()

  case fetch_manifold_market(market_id) {
    Ok(mkt) -> {
      // 1. Update probability history (keep last 200)
      let new_history = [mkt.probability, ..list.take(history, 199)]

      //    Use std_dev and sma as basic features — volume_list from volume
      let volume_float_list = [mkt.volume, ..list.take(list.repeat(mkt.volume, 199), 199)]
      let volume_list = list.map(volume_float_list, float.truncate)
      let alpha_vector = analytics.calculate_all_metrics_with_time(
        new_history, volume_list, ts
      )

      // 3. Create and ingest prediction tick
      let tick = market.PredictionTick(
        market_id: "pm_" <> market_id,
        outcome: "YES",
        probability: mkt.probability,
        volume: float.truncate(mkt.volume),
        timestamp: ts,
        trader_id: "manifold_poll"
      )
      
      // Ingest via Batcher
      process.send(batcher, ingest_batcher.Ingest(tick, alpha_vector))

      // 4. Broadcast to paper trader (probability as "price" for strategy)
      case trader {
        Some(t) -> paper_trader.broadcast_tick(t, mkt.probability, alpha_vector)
        None -> Nil
      }

      // 5. Log
      let vol_short = analytics.std_dev(list.take(new_history, 10))
      io.println("🎲 Prediction [pm_" <> market_id <> "]: "
        <> mkt.question
        <> " | P=" <> float.to_string(mkt.probability)
        <> " | Vol: " <> float.to_string(mkt.volume)
        <> " | σ(10): " <> float.to_string(vol_short))

      // 6. Check resolution
      case mkt.is_resolved {
        True -> {
          io.println("🏁 Market RESOLVED: " <> mkt.question
            <> " → " <> mkt.resolution)
          // Don't loop — market is done
          Nil
        }
        False -> {
          process.sleep(15_000)
          loop(batcher, market_id, new_history, trader, notifier_actor)
        }
      }
    }
    Error(e) -> {
      process.send(notifier_actor, notifier.Notify(types.SystemHealth("MarketFeed", "Error [" <> market_id <> "]: " <> e)))
      process.sleep(15_000)
      loop(batcher, market_id, history, trader, notifier_actor)
    }
  }
}

/// Fetch a market from the Manifold Markets API.
/// GET https://api.manifold.markets/v0/market/{slug}
fn fetch_manifold_market(market_id: String) -> Result(ManifoldMarket, String) {
  let url = "https://api.manifold.markets/v0/slug/" <> market_id
  let req_result = request.to(url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req_result)

  case hackney.send(req) {
    Ok(resp) if resp.status == 200 -> decode_manifold(resp.body)
    Ok(resp) -> Error("API returned status " <> int.to_string(resp.status))
    Error(e) -> Error("HTTP request failed: " <> string.inspect(e))
  }
}

/// Decode Manifold API JSON response.
/// Handles both binary (probability) and multi-outcome markets.
fn decode_manifold(json_str: String) -> Result(ManifoldMarket, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use question <- decode.field("question", decode.string)
    use probability <- decode.optional_field("probability", 0.5, decode.float)
    use volume <- decode.optional_field("volume", 0.0, decode.float)
    use close_time <- decode.optional_field("closeTime", 0, decode.int)
    use is_resolved <- decode.optional_field("isResolved", False, decode.bool)
    use resolution <- decode.optional_field("resolution", "", decode.string)
    decode.success(ManifoldMarket(
      id: id,
      question: question,
      probability: probability,
      volume: volume,
      close_time: close_time,
      is_resolved: is_resolved,
      resolution: resolution
    ))
  }

  case json.parse(from: json_str, using: decoder) {
    Ok(m) -> Ok(m)
    Error(_) -> Error("Manifold JSON decode failed")
  }
}

// --- PolyMarket Integration ---

pub type PolyMarket {
  PolyMarket(
    id: String,
    question: String,
    active: Bool,
    closed: Bool,
    volume: Float
  )
}

pub type PolyMarketTrade {
  PolyMarketTrade(
    asset_id: String,
    price: Float,
    size: Float,
    side: String,
    timestamp: Int
  )
}

/// Start a PolyMarket feed for a specific list of market IDs (Token IDs).
pub fn start_polymarket_feed(
  batcher: process.Subject(ingest_batcher.Message),
  market_ids: List(String),
  trader: Option(process.Subject(paper_trader.Message)),
  analyst: Option(process.Subject(analyst.Message)),
  notifier_actor: process.Subject(notifier.Message)
) {
  list.each(market_ids, fn(mid) {
    process.spawn_unlinked(fn() {
      io.println("🔵 PolyMarket Feed: Tracking [" <> mid <> "]")
      poly_loop(batcher, mid, [], trader, analyst, notifier_actor, 1000, -1.0)
    })
  })
}

fn poly_loop(
  batcher: process.Subject(ingest_batcher.Message),
  market_id: String,
  history: List(Float),
  trader: Option(process.Subject(paper_trader.Message)),
  analyst: Option(process.Subject(analyst.Message)),
  notifier_actor: process.Subject(notifier.Message),
  current_sleep: Int,
  last_price: Float
) {
  let ts = erlang_system_time()
  
  // For PolyMarket, we fetch the price of the 'YES' token (Outcome 1 usually)
  // GET https://clob.polymarket.com/price?token_id=...
  case fetch_poly_price(market_id) {
    Ok(price) -> {
       // 1. Update history
       let new_history = [price, ..list.take(history, 199)]
       
       // Mock volume for now as price endpoint doesn't return it
       let volume_list = list.repeat(0, 200) 
       
       let alpha_vector = analytics.calculate_all_metrics_with_time(
         new_history, volume_list, ts
       )

       // 3. Create prediction tick
        let tick = market.PredictionTick(
          market_id: "pm_" <> market_id, // Prefix to namespace it
          outcome: "YES",
          probability: price,
          volume: 0, // No volume from simple price endpoint
          timestamp: ts,
          trader_id: "polymarket_poll"
        )

       process.send(batcher, ingest_batcher.Ingest(tick, alpha_vector))
       
       case trader {
         Some(t) -> paper_trader.broadcast_tick(t, price, alpha_vector)
         None -> Nil
       }

       // 4. Push to Causal Analyst
       case analyst {
         Some(a) -> process.send(a, analyst.MarketUpdate(market_id, price, alpha_vector))
         None -> Nil
       }
       
       // Adaptive Polling Logic:
       // If price is stagnant, backoff exponentially. If price moves, wake up immediately.
       let next_sleep = case price == last_price {
         True -> int.min(current_sleep * 2, 30_000) // Max 30s sleep
         False -> 1000 // Reset to 1s on activity
       }
       
       case next_sleep > 5000 {
         True -> io.println("💤 Poly [" <> market_id <> "] Stagnant. Sleeping " <> int.to_string(next_sleep) <> "ms")
         False -> io.println("🔵 Poly [" <> market_id <> "]: " <> float.to_string(price))
       }
       
       process.sleep(next_sleep)
       poly_loop(batcher, market_id, new_history, trader, analyst, notifier_actor, next_sleep, price)
    }
    Error(e) -> {
      process.send(notifier_actor, notifier.Notify(types.SystemHealth("PolyFeed", "Error [" <> market_id <> "]: " <> e)))
      process.sleep(5000)
      poly_loop(batcher, market_id, history, trader, analyst, notifier_actor, 1000, last_price)
    }
  }
}

fn fetch_poly_price(token_id: String) -> Result(Float, String) {
  let url = "https://clob.polymarket.com/price?side=BUY&token_id=" <> token_id
  let req_result = request.to(url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req_result)
  
  // Use hackney for robust handling
  case hackney.send(req) {
     Ok(resp) if resp.status == 200 -> {
       let decoder = decode.at(["price"], decode.string |> decode.then(fn(s) {
         case float.parse(s) {
           Ok(f) -> decode.success(f)
           Error(_) -> {
             // Fallback: try parsing as int (e.g. "0")
             case int.parse(s) {
               Ok(i) -> decode.success(int.to_float(i))
               Error(_) -> decode.failure(0.0, "Float (or Int string)")
             }
           }
         }
       }))
       json.parse(resp.body, decoder)
       |> result.map_error(fn(e) { "JSON Decode Error: " <> string.inspect(e) })
     }
     Ok(resp) -> Error("API Status: " <> int.to_string(resp.status))
     Error(e) -> Error("HTTP Request Failed: " <> string.inspect(e))
  }
}

/// Fetch active token IDs from PolyMarket Gamma API.
pub fn fetch_active_tokens() -> Result(List(String), String) {
  let url = "https://gamma-api.polymarket.com/markets?active=true&closed=false&enableOrderBook=true&limit=20"
  let req_result = request.to(url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req_result)
  
  case hackney.send(req) {
     Ok(resp) if resp.status == 200 -> {
       let market_decoder = {
         use enable_ob <- decode.optional_field("enableOrderBook", False, decode.bool)
         use ids_str <- decode.optional_field("clobTokenIds", "[]", decode.string)
         
         case enable_ob {
           True -> {
             case json.parse(ids_str, decode.list(decode.string)) {
                Ok(ids) -> decode.success(ids)
                Error(_) -> decode.success([])
             }
           }
           False -> decode.success([])
         }
       }
       
       json.parse(resp.body, decode.list(market_decoder))
       |> result.map(fn(lists) { 
         // Take only the first token from each market (usually the 'YES' outcome)
         list.filter_map(lists, fn(ids) { list.first(ids) })
         |> list.unique() 
       })
       |> result.map_error(fn(e) { 
         "JSON Decode Error: " <> string.inspect(e) 
       })
     }
     Ok(resp) -> Error("API Status: " <> int.to_string(resp.status))
     Error(e) -> Error("HTTP Request Failed: " <> string.inspect(e))
  }
}

@external(erlang, "erlang", "system_time")
fn do_system_time(unit: Int) -> Int

fn erlang_system_time() -> Int {
  do_system_time(1000)
}
