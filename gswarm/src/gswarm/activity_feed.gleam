import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/result
import gleam/list
import gleam/io
import gleam/string
import gleam/int
import gleam/dynamic/decode
import gleam/erlang/process
import gswarm/leaderboard
import gswarm/amka_domain

const data_url = "https://data-api.polymarket.com"

fn decode_numeric() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [
    decode.int |> decode.map(int.to_float)
  ])
}

/// Fetch top traders from PolyMarket leaderboard.
pub fn fetch_leaderboard() -> Result(List(String), String) {
  let url = data_url <> "/v1/leaderboard?limit=20&window=all"
  let req_result = request.to(url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req_result)
  
  // Anti-bot mitigation: PolyMarket requires User-Agent
  let req = request.set_header(req, "User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
  
  case httpc.send(req) {
    Ok(resp) if resp.status == 200 -> {
      let decoder = {
        use address <- decode.field("proxyWallet", decode.string)
        decode.success(address)
      }
      json.parse(resp.body, decode.list(decoder))
      |> result.map_error(fn(e) { "JSON Decode Error: " <> string.inspect(e) })
    }
    Ok(resp) -> {
      Error("API returned status " <> string.inspect(resp.status))
    }
    _ -> Error("Failed to send HTTP request")
  }
}

pub type ActivityFeedConfig {
  ActivityFeedConfig(
    lb_actor: process.Subject(leaderboard.Message),
    users: List(String)
  )
}

pub fn start_with_dedup(lb_actor, users: List(String)) {
  list.each(users, fn(user) {
     io.println("🕵️ ActivityFeed (Dedup): Tracking user [" <> user <> "]")
  })
  io.println("📡 Activity Feed: Starting background polling (5min intervals)")
  
  // Spawn background polling loop
  process.spawn(fn() {
    poll_trader_activities(ActivityFeedConfig(lb_actor, users))
  })
}

fn poll_trader_activities(config: ActivityFeedConfig) {
  io.println("📊 Activity Feed: Polling " <> string.inspect(list.length(config.users)) <> " traders...")
  
  // Poll each trader's recent activity
  list.each(config.users, fn(user_address) {
    case fetch_user_trades(user_address) {
      Ok(trades) -> {
        case list.length(trades) {
          0 -> Nil
          n -> {
            io.println("  └─ Trader [" <> user_address <> "]: " <> string.inspect(n) <> " trades")
            list.each(trades, fn(trade) {
              process.send(config.lb_actor, leaderboard.ProcessActivity(trade))
            })
          }
        }
      }
      Error(e) -> {
        io.println("  └─ Trader [" <> user_address <> "] Error: " <> e)
      }
    }
  })
  
  // Wait then loop
  process.sleep(300_000)
  poll_trader_activities(config)
}

fn fetch_user_trades(user_address: String) -> Result(List(amka_domain.TradeActivity), String) {
  // PolyMarket API endpoint for user trades
  let url = data_url <> "/trades?user=" <> user_address <> "&limit=20"
  let req_result = request.to(url) |> result.map_error(fn(_) { "Invalid URL" })
  use req <- result.try(req_result)
  
  let req = request.set_header(req, "User-Agent", "Mozilla/5.0")
  
  case httpc.send(req) {
    Ok(resp) if resp.status == 200 -> {
      decode_trades(resp.body, user_address)
    }
    _ -> Error("Failed to fetch trades")
  }
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
      "SELL" -> amka_domain.Sell
      _ -> amka_domain.Buy
    }
    
    decode.success(amka_domain.TradeActivity(
      user: user_address,
      market_title: title,
      market_slug: slug,
      trade_type: trade_type,
      size: size,
      price: price,
      usdc_size: price *. size,
      timestamp: timestamp,
    ))
  }
  
  json.parse(json_str, decode.list(trade_decoder))
  |> result.map_error(fn(e) { "Failed to decode trades: " <> string.inspect(e) })
}
