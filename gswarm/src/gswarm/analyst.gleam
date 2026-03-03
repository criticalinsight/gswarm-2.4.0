import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleamdb
import gleamdb/fact
import gleamdb/sharded
import gleamdb/shared/types
import gswarm/reflexion
import gleam/dict

// The Causal Engine: Finds similar historical patterns and predicts probability movements.
// Now Event-Driven: Reacts to MarketUpdate triggers.

pub type Message {
  MarketUpdate(market_id: String, price: Float, vector: List(Float))
}

pub type State {
  State(sharded_db: sharded.ShardedDb, primary_db: gleamdb.Db)
}

pub fn start_analyst(db: sharded.ShardedDb) -> Result(Subject(Message), actor.StartError) {
  // Assume Shard 0 is primary for now, or just pick one
  let assert Ok(primary) = dict.get(db.shards, 0)
  
  let res = actor.new(State(sharded_db: db, primary_db: primary))
    |> actor.on_message(handle_message)
    |> actor.start()
    
  case res {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    MarketUpdate(market_id, price, vector) -> {
      analyze_market(state.sharded_db, state.primary_db, market_id, price, vector)
      actor.continue(state)
    }
  }
}

fn analyze_market(
  sharded_db: sharded.ShardedDb,
  db: gleamdb.Db,
  market_id: String,
  current_prob: Float,
  latest_vec: List(Float)
) {
  // Find historical matches (k=5)
  let query = [
    types.Similarity("v", latest_vec, 0.85)
  ]
  
  let matches = gleamdb.query(db, query)
  let count = list.length(matches.rows)
  
  case count > 1 {
    True -> {
      let fractals = count - 1
      
      // Derive prediction direction from fractal count
      let direction = case fractals > 3 {
        True -> "probability_up"
        False -> "probability_down"
      }
      
      // Predict probability magnitude based on fractal confidence
      let delta = int.to_float(fractals) *. 0.02  // 2% per fractal
      let raw_prob = case direction {
        "probability_up" -> float.min(current_prob +. delta, 1.0)
        _ -> float.max(current_prob -. delta, 0.0)
      }
      
      // PHASE 52: Semantic Reflexion (Check for prior mistakes)
      let #(adjusted_prob, reflex_note) = case reflexion.get_correction(sharded_db, latest_vec) {
        Ok(correction) -> {
          let adj = reflexion.apply_correction(raw_prob, correction)
          #(adj, " [Reflexion: " <> correction.lesson <> "]")
        }
        Error(_) -> #(raw_prob, "")
      }
      
      let confidence_str = int.to_string(fractals) <> " fractals" <> reflex_note
      
      io.println("🔮 Analyst [" <> market_id <> "]: " <> direction
        <> " | Current: " <> float.to_string(current_prob)
        <> " | Predicted: " <> float.to_string(adjusted_prob)
        <> " | Reason: " <> confidence_str)
      
      // Record prediction for Brier scoring (capture vector for future reflexion)
      record_probability_prediction(db, market_id, direction, current_prob, adjusted_prob, confidence_str, latest_vec)
    }
    False -> Nil // No similar patterns, stay silent (Signal > Noise)
  }
}

/// Record a probability prediction for future Brier scoring.
/// Stores current and predicted probability so resolution.gleam can compare.
fn record_probability_prediction(
  db: gleamdb.Db,
  market_id: String,
  direction: String,
  current_probability: Float,
  predicted_probability: Float,
  reason: String,
  vector: List(Float)
) {
  let ts = erlang_system_time()
  let pred_id = "pred_" <> market_id <> "_" <> int.to_string(ts)
  let lookup = fact.Lookup(#("prediction/id", fact.Str(pred_id)))

  let facts = [
    #(lookup, "prediction/id", fact.Str(pred_id)),
    #(lookup, "prediction/market_id", fact.Str(market_id)),
    #(lookup, "prediction/direction", fact.Str(direction)),
    #(lookup, "prediction/current_probability", fact.Float(current_probability)),
    #(lookup, "prediction/predicted_probability", fact.Float(predicted_probability)),
    #(lookup, "prediction/reason", fact.Str(reason)),
    #(lookup, "prediction/context_vector", fact.Vec(vector)),
    #(lookup, "prediction/timestamp", fact.Int(ts)),
    #(lookup, "prediction/status", fact.Str("pending"))
  ]
  let _ = gleamdb.transact(db, facts)
  Nil
}

@external(erlang, "erlang", "system_time")
fn do_system_time(unit: Int) -> Int

fn erlang_system_time() -> Int {
  do_system_time(1000)
}
