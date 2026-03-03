import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/http/request
import gleam/httpc
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
import gleam/option.{type Option, None, Some}

pub fn start_live_ticker(
  batcher: process.Subject(ingest_batcher.Message),
  market_id: String,
  asset_pair: String,
  trader: Option(process.Subject(paper_trader.Message)),
  notifier_actor: process.Subject(notifier.Message)
) {
  process.spawn_unlinked(fn() {
    loop(batcher, market_id, asset_pair, [], trader, notifier_actor)
  })
}

fn loop(
  batcher: process.Subject(ingest_batcher.Message),
  market_id: String,
  asset_pair: String,
  history: List(#(Float, Int)),
  trader: Option(process.Subject(paper_trader.Message)),
  notifier_actor: process.Subject(notifier.Message)
) {
  let ts = erlang_system_time()

  case fetch_ticker(asset_pair) {
    Ok(#(price, volume)) -> {
      // 1. Update History (Keep last 200 ticks)
      let new_history = [#(price, volume), ..list.take(history, 199)]

      let price_list = list.map(new_history, fn(h) { h.0 })
      let volume_list = list.map(new_history, fn(h) { h.1 })

      // 2. Calculate Alpha Vector WITH temporal features (Phase 33)
      let alpha_vector = analytics.calculate_all_metrics_with_time(
        price_list, volume_list, ts
      )

      let _tick = market.Tick(
        market_id: market_id,
        outcome: "Yes",
        price: price,
        volume: volume,
        timestamp: ts,
        trader_id: "live_feed"
      )

      // Ingest via Batcher (Phase 43 Adaptive Ticking)
      process.send(batcher, ingest_batcher.Ingest(
        market.PredictionTick(market_id, "Yes", price /. 100_000.0, volume, ts, "live_feed"), // Mock prob for legacy
        alpha_vector
      ))

      // 4. Broadcast to Paper Trader (if any)
      case trader {
        Some(t) -> paper_trader.broadcast_tick(t, price, alpha_vector)
        None -> Nil
      }

      // Logging & Adaptive Polling
      let vol_short = analytics.std_dev(list.take(price_list, 10))
      io.println("📡 Alpha [" <> market_id <> "]: " <> asset_pair
        <> " $" <> float.to_string(price)
        <> " | Vol: " <> int.to_string(volume)
        <> " | σ(10): " <> float.to_string(vol_short))

      // Adaptive Polling: 
      // High Volatility -> 5s
      // Low Volatility -> 30s
      let sleep_ms = case vol_short >. 5.0 {
        True -> 5000
        False -> 30000
      }
      
      process.sleep(sleep_ms)
      loop(batcher, market_id, asset_pair, new_history, trader, notifier_actor)
    }
    Error(e) -> {
      process.send(notifier_actor, notifier.Notify(types.SystemHealth("LiveTicker", "Error [" <> asset_pair <> "]: " <> e)))
      process.sleep(30000) // Longer sleep on error in lean mode
      loop(batcher, market_id, asset_pair, history, trader, notifier_actor)
    }
  }
}

/// Fetch price AND volume from Coinbase ticker endpoint.
/// Falls back to spot price with mock volume if ticker fails.
fn fetch_ticker(asset: String) -> Result(#(Float, Int), String) {
  // Try the products ticker endpoint first (has volume)
  let ticker_url = "https://api.exchange.coinbase.com/products/" <> asset <> "/ticker"
  let req_result = request.to(ticker_url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req_result)

  case httpc.send(req) {
    Ok(resp) if resp.status == 200 -> decode_ticker(resp.body)
    _ -> {
      // Fallback: spot price, mock volume
      case fetch_spot_price(asset) {
        Ok(price) -> Ok(#(price, 0))
        Error(e) -> Error(e)
      }
    }
  }
}

/// Decode Coinbase Exchange ticker: {"price":"96000.50","volume":"1234.56","trade_id":...}
fn decode_ticker(json_str: String) -> Result(#(Float, Int), String) {
  let decoder = {
    use price_str <- decode.field("price", decode.string)
    use vol_str <- decode.field("volume", decode.string)
    decode.success(#(price_str, vol_str))
  }

  case json.parse(from: json_str, using: decoder) {
    Ok(#(price_str, vol_str)) -> {
      use price <- result.try(
        float.parse(price_str) |> result.replace_error("Invalid price")
      )
      // Volume is a float string (e.g. "1234.56"), truncate to int
      let volume = case float.parse(vol_str) {
        Ok(v) -> float.truncate(v)
        Error(_) -> 0
      }
      Ok(#(price, volume))
    }
    Error(_) -> Error("Ticker JSON decode failed")
  }
}

/// Fallback: original Coinbase spot API
fn fetch_spot_price(asset: String) -> Result(Float, String) {
  let url = "https://api.coinbase.com/v2/prices/" <> asset <> "/spot"
  let req_result = request.to(url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req_result)

  use resp <- result.try(httpc.send(req) |> result.map_error(fn(_) { "HTTP Error" }))

  case resp.status {
    200 -> decode_coinbase(resp.body)
    _ -> Error("API returned status " <> int.to_string(resp.status))
  }
}

fn decode_coinbase(json_str: String) -> Result(Float, String) {
  let decoder = {
    use data <- decode.field("data", {
       use amount <- decode.field("amount", decode.string)
       decode.success(amount)
    })
    decode.success(data)
  }

  case json.parse(from: json_str, using: decoder) {
    Ok(amount_str) -> float.parse(amount_str) |> result.replace_error("Invalid float format")
    Error(_) -> Error("JSON Decode Failed")
  }
}

@external(erlang, "erlang", "system_time")
fn do_system_time(unit: Int) -> Int

fn erlang_system_time() -> Int {
  do_system_time(1000)
}
