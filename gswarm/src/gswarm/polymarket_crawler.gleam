import gleam/http/request
import gleam/hackney
import gleam/json
import gleam/result
import gleam/list
import gleam/io
import gleam/string
import gleam/int
import gleam/float
import gleam/dynamic/decode
import gleam/erlang/process
import gswarm/amka_domain
import gswarm/market
import gleamdb
import gleamdb/q
import gswarm/scout

const data_url = "https://data-api.polymarket.com"

pub type CrawlerMessage {
  CrawlMarkets(limit: Int)
  CrawlTraders(market_id: String, limit: Int)
  IngestTraderHistory(address: String)
}

pub fn start_crawler(db: gleamdb.Db) {
  process.spawn_unlinked(fn() {
    io.println("🕷️ PolyMarket Crawler: Initialized. Scaling to 50k traders...")
    crawler_loop(db, 0)
  })
}

fn crawler_loop(db: gleamdb.Db, offset: Int) {
  // 1. Fetch active markets with pagination
  case fetch_active_markets(offset) {
    Ok(mids) if mids != [] -> {
      list.each(mids, fn(mid) {
        crawl_market_traders(db, mid)
        process.sleep(1000) // Rate limiting
      })
      // Loop with next offset
      crawler_loop(db, offset + 100)
    }
    _ -> {
      io.println("🕷️ Crawler: Reached end of active markets or error. Resetting...")
      process.sleep(60_000)
      crawler_loop(db, 0)
    }
  }
}

fn fetch_active_markets(offset: Int) -> Result(List(String), String) {
  let url = "https://gamma-api.polymarket.com/markets?active=true&closed=false&limit=100&offset=" <> int.to_string(offset)
  let req = request.to(url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req)
  let req = request.set_header(req, "User-Agent", "Mozilla/5.0")
  
  case hackney.send(req) {
    Ok(resp) if resp.status == 200 -> {
      let decoder = {
        use id <- decode.field("id", decode.string)
        use category <- decode.field("category", decode.string)
        decode.success(#(id, category))
      }
      
      json.parse(resp.body, decode.list(decoder))
      |> result.map(fn(markets) {
        markets
        |> list.filter(fn(m) { scout.should_track_market(m.1) })
        |> list.map(fn(m) { m.0 })
      })
      |> result.map_error(fn(e) { "Decode Error: " <> string.inspect(e) })
    }
    _ -> Error("API Failed")
  }
}

fn crawl_market_traders(db: gleamdb.Db, market_id: String) {
  // Discover traders from recent trades in this market
  let url = data_url <> "/trades?marker_id=" <> market_id <> "&limit=100"
  let req = request.to(url) |> result.unwrap(request.new())
  let req = request.set_header(req, "User-Agent", "Mozilla/5.0")
  
  case hackney.send(req) {
    Ok(resp) if resp.status == 200 -> {
      let decoder = decode.at(["proxyWallet"], decode.string)
      case json.parse(resp.body, decode.list(decoder)) {
        Ok(addresses) -> {
          let unique_addresses = list.unique(addresses)
          io.println("🕷️ Crawler: Found " <> int.to_string(list.length(unique_addresses)) <> " traders in market " <> market_id)
          list.each(unique_addresses, fn(addr) {
            process.spawn_unlinked(fn() { ingesting_historical_data(db, addr) })
          })
        }
        _ -> Nil
      }
    }
    _ -> Nil
  }
}

fn ingesting_historical_data(db: gleamdb.Db, address: String) {
  let url = data_url <> "/trades?user=" <> address <> "&limit=100"
  let req = request.to(url) |> result.unwrap(request.new())
  let req = request.set_header(req, "User-Agent", "Mozilla/5.0")
  
  case hackney.send(req) {
    Ok(resp) if resp.status == 200 -> {
      case decode_trades(resp.body, address) {
        Ok(trades) -> {
          // Smart Backward Crawl: Check if the *latest* trade (first in list) exists.
          // If it does, we assume we've already crawled this history.
          let should_crawl = case list.first(trades) {
            Ok(latest) -> !check_head_exists(db, latest.market_slug, address, latest.timestamp)
            Error(_) -> False
          }

          case should_crawl {
            True -> {
              io.println("📥 Ingesting " <> int.to_string(list.length(trades)) <> " historical trades for " <> address)
              list.each(trades, fn(trade) {
                let tick = market.PredictionTick(
                  market_id: trade.market_slug,
                  outcome: "YES", // Approximation
                  probability: trade.price,
                  volume: float.truncate(trade.size),
                  timestamp: trade.timestamp,
                  trader_id: address
                )
                // Use existing ingest logic
                let _ = market.ingest_batch_with_vectors(db, [#(tick, [])])
              })
            }
            False -> io.println("⏭️ Skipping " <> address <> ": Head exists (Smart Crawl)")
          }
        }
        _ -> Nil
      }
    }
    _ -> Nil
  }
}

fn check_head_exists(db: gleamdb.Db, market_id: String, trader_id: String, timestamp: Int) -> Bool {
  let query = q.new()
    |> q.where(q.v("t"), "tick/market", q.s("pm_" <> market_id))
    |> q.where(q.v("t"), "tick/trader", q.s(trader_id))
    |> q.where(q.v("t"), "tick/timestamp", q.i(timestamp))
    |> q.limit(1)
    |> q.to_clauses()
    
  let matches = gleamdb.query(db, query)
  matches.rows != []
}

fn decode_trades(json_str: String, user_address: String) -> Result(List(amka_domain.TradeActivity), String) {
  let trade_decoder = {
    use title <- decode.field("title", decode.string)
    use slug <- decode.field("slug", decode.string)
    use side <- decode.field("side", decode.string)
    use price <- decode.field("price", decode_numeric())
    use size <- decode.field("size", decode_numeric())
    use timestamp <- decode.field("timestamp", decode.int)
    
    let trade_type = case side {
      "BUY" -> amka_domain.Buy
      _ -> amka_domain.Sell
    }
    
    decode.success(amka_domain.TradeActivity(
      user: user_address,
      market_title: title,
      market_slug: slug,
      trade_type: trade_type,
      size: size,
      price: price,
      usdc_size: price *. size,
      timestamp: timestamp
    ))
  }
  
  json.parse(json_str, decode.list(trade_decoder))
  |> result.map_error(fn(_) { "Decode Failed" })
}

fn decode_numeric() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [
    decode.int |> decode.map(int.to_float)
  ])
}
