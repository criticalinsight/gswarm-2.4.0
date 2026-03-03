import gleam/io
import gleam/list
import gleam/dict
import gleamdb
import gleamdb/shared/types.{Var}
import gleamdb/fact
import gswarm/semantic
import gswarm/market
import gleam/int

pub fn index_market_semantics(db: gleamdb.Db, market_id: String, question: String) {
  let embedding = semantic.generate_embedding(question)
  
  let facts = [
    #(fact.Lookup(#("market/id", fact.Str(market_id))), "market/embedding", fact.Vec(embedding))
  ]
  
  gleamdb.transact(db, facts)
}

pub fn find_similar_markets(db: gleamdb.Db, question: String) {
  let target_vector = semantic.generate_embedding(question)
  
  // Use GleamDB's Vector Sovereignty: Datalog + Similarity Join
  let query = [
    gleamdb.p(#(Var("e"), "market/id", Var("id"))),
    types.Similarity(variable: "e", vector: target_vector, threshold: 0.8)
  ]
  
  let results = gleamdb.query(db, query)
  
  case list.is_empty(results.rows) {
    True -> io.println("🧠 Context: No similar markets found.")
    False -> {
      io.println("🧠 Context: Found " <> int.to_string(list.length(results.rows)) <> " similar markets.")
      list.each(results.rows, fn(r) {
        case dict.get(r, "id") {
          Ok(fact.Str(id)) -> io.println("   - " <> id)
          _ -> Nil
        }
      })
    }
  }
}


pub fn detect_anomaly(db: gleamdb.Db, tick: market.Tick) -> Bool {
  let vec = market.tick_to_vector(tick)
  
  // Find nearest neighbor in "normal" cluster
  let query = [
    // We search across ALL ticks (global anomaly detection)
    types.Similarity("v", vec, 0.95) // Very high similarity means normal
  ]
  
  let results = gleamdb.query(db, query)
  
  // If no very similar tick exists, it's an anomaly (or new regime)
  list.is_empty(results.rows)
}
