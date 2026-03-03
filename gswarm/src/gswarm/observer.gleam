import gleam/io
import gleam/string
import gleamdb
import gleamdb/fact
import gleamdb/engine

pub fn pulse_market(db: gleamdb.Db, market_id: String) {
  // Use gleamdb.pull to get a structured snapshot of the market identity.
  // This demonstrates structured data retrieval vs triple queries.
  let pattern = [
    engine.Attr("market/id"),
    engine.Attr("market/question")
  ]
  
  let result = gleamdb.pull(db, fact.Lookup(#("market/id", fact.Str(market_id))), pattern)
  
  case result {
    engine.Map(data) -> {
      io.println("🧠 Observer Pulse: Market Snapshot")
      io.println("   ID: " <> string.inspect(data))
    }
    _ -> io.println("⚠️ Observer Pulse: Failed to capture market " <> market_id)
  }
}
