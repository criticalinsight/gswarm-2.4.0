import gleam/int
import gleam/float
import gleam/list
import gleam/string
import gleam/dict
import gleamdb
import gleamdb/shared/types as db_types
import gleamdb/fact
import gswarm/leaderboard.{type Stats}
import gswarm/amka_domain.{type TradeActivity, Buy, Sell, Redeem}

import gswarm/ai_brain

pub fn generate_trader_report(db: gleamdb.Db, stats: Stats) -> String {
  let header = "🕵️ <b>Sovereign Trader Report</b>: <code>" <> stats.trader_id <> "</code>\n\n"
    <> "<b>Performance Summary</b>\n"
    <> "• <b>ROI</b>: " <> float.to_string(stats.roi) <> "%\n"
    <> "• <b>Total Trades</b>: " <> int.to_string(stats.prediction_count) <> "\n"
    <> "• <b>Total PnL</b>: $" <> float.to_string(stats.total_pnl) <> "\n\n"

  let nexus_string = build_nexus_context(db, stats)
  
  let ai_assessment = case ai_brain.assess_trader(nexus_string) {
    Ok(text) -> text
    Error(e) -> "⚠️ AI Assessment Failed: " <> e
  }

  let activity_report = generate_activity_context(db, stats.recent_activity)

  let report = header <> "<b>Sovereign Success Rationale</b>\n" <> ai_assessment <> "\n\n" <> activity_report
  
  case string.length(report) > 4000 {
    True -> string.slice(report, 0, 3997) <> "..."
    False -> report
  }
}

fn build_nexus_context(db: gleamdb.Db, stats: Stats) -> String {
  let performance = "Trader ROI: " <> float.to_string(stats.roi) <> "%, Total Trades: " <> int.to_string(stats.prediction_count) <> "\n"
  let activity = list.map(stats.recent_activity, fn(trade) {
    let news = fetch_news_context(db, trade.timestamp)
    let context = list.fold(news, "", fn(acc, n) { acc <> " [News: " <> n.title <> " at " <> int.to_string(n.ts) <> "]" })
    "Trade: " <> trade.market_title <> " at " <> int.to_string(trade.timestamp) <> " Price: " <> float.to_string(trade.price) <> " Context: " <> context
  }) |> string.join("\n")
  
  performance <> activity
}

fn generate_activity_context(db: gleamdb.Db, activity: List(TradeActivity)) -> String {
  let report_lines = list.map(activity, fn(trade) {
    let news_context = fetch_news_context(db, trade.timestamp)
    let trade_desc = case trade.trade_type {
      Buy -> "🟢 BOUGHT"
      Sell -> "🔴 SOLD"
      Redeem -> "⚪ REDEEMED"
    }
    
    let line = "<b>[" <> int.to_string(trade.timestamp) <> "]</b> " <> trade_desc <> " " <> trade.market_title <> "\n"
      <> "  • <b>Price</b>: $" <> float.to_string(trade.price) <> "\n"
      <> "  • <b>Size</b>: " <> float.to_string(trade.usdc_size) <> " USDC\n"
    
    case news_context {
      [] -> line <> "  • <b>Context</b>: No significant news detected in window.\n\n"
      items -> {
        let news_md = list.fold(items, "  • <b>Information Available</b>:\n", fn(acc, item) {
          acc <> "    • 📰 " <> item.title <> " (" <> int.to_string(item.ts) <> ")\n"
        })
        line <> news_md <> "\n"
      }
    }
  })

  "<b>Recent Trade Nexus</b>\n" <> string.join(report_lines, "\n")
}

pub type NewsContextItem {
  NewsContextItem(title: String, ts: Int)
}

fn fetch_news_context(db: gleamdb.Db, trade_ts: Int) -> List(NewsContextItem) {
  let news_query = [
    db_types.Positive(#(db_types.Var("n"), "news/title", db_types.Var("title"))),
    db_types.Positive(#(db_types.Var("n"), "news/timestamp", db_types.Var("ts")))
  ]
  let results = gleamdb.query(db, news_query)
  
  // Pivot: News 30m before to 5m after
  list.filter_map(results.rows, fn(row) {
    case dict.get(row, "title"), dict.get(row, "ts") {
      Ok(fact.Str(title)), Ok(fact.Int(ts)) -> {
        case ts >= trade_ts - 1800 && ts <= trade_ts + 300 {
          True -> Ok(NewsContextItem(title, ts))
          False -> Error(Nil)
        }
      }
      _, _ -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) { int.compare(b.ts, a.ts) })
}
