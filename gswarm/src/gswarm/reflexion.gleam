import gleam/io
import gleam/list

@external(erlang, "erlang", "phash2")
fn phash2(term: a) -> Int

@external(erlang, "os", "system_time")
fn system_time() -> Int
import gleamdb
import gleamdb/fact
import gleamdb/sharded

pub type Correction {
  Correction(
    id: String,
    vector: List(Float),
    lesson: String, // "invert", "veto", "boost"
    weight: Float,
    timestamp: Int
  )
}

/// Analyze a failed prediction and store a Correction Fact.
/// Triggered when Brier Score > 0.25 (worse than random).
pub fn analyze_failure(
  db: gleamdb.Db,
  prediction_id: String,
  _market_id: String,
  context_vector: List(Float),
  predicted_dir: String,
  actual_outcome: String
) {
  let ts = system_time()
  
  // 1. Determine the Lesson
  // If we predicted UP and it went DOWN -> Lesson is "Invert" or "Veto"
  // If we predicted DOWN and it went UP -> Lesson is "Invert" or "Veto"
  let lesson = case predicted_dir, actual_outcome {
    "probability_up", "NO" -> "invert" // Predicted YES/UP, outcome NO/DOWN
    "probability_down", "YES" -> "invert" // Predicted NO/DOWN, outcome YES/UP
    _, _ -> "veto" // Unknown mismatch, just be careful next time
  }
  
  // 2. Create Correction Fact
  // Use deterministic UID based on prediction_id to ensure we don't duplicate if run twice
  let corr_id = "corr_" <> prediction_id
  let eid_int = phash2(corr_id)
  let eid = fact.Uid(fact.EntityId(eid_int))
  
  let facts = [
    #(eid, "correction/id", fact.Str(corr_id)),
    #(eid, "correction/ref_prediction", fact.Str(prediction_id)),
    #(eid, "correction/vector", fact.Vec(context_vector)),
    #(eid, "correction/lesson", fact.Str(lesson)),
    #(eid, "correction/weight", fact.Float(0.5)), // Start with 50% correction weight
    #(eid, "correction/timestamp", fact.Int(ts))
  ]
  
  let res = gleamdb.transact(db, facts)
  case res {
    Ok(_) -> io.println("🧠 Reflexion: Analyzed failure [" <> prediction_id <> "]. Stored lesson [" <> lesson <> "] for vector context.")
    Error(e) -> io.println("❌ Reflexion: Transaction FAILED: " <> e)
  }
}

/// Retrieve relevant corrections for a given vector context.
/// Uses Phase 50 Global Vector Search.
import gleam/dict
import gleamdb/shared/types

pub fn get_correction(
  sharded_db: sharded.ShardedDb,
  current_vector: List(Float)
) -> Result(Correction, Nil) {
  // 1. Search for similar "Failure Modes"
  // We want vectors that led to failure.
  let results = sharded.global_vector_search(sharded_db, current_vector, 0.9, 1) // High threshold
  
  case list.first(results) {
    Ok(res) -> {
       // Fetch correction details from Primary Shard (Stub: assuming stored on shard 0)
       case dict.get(sharded_db.shards, 0) {
         Ok(primary) -> {
           let eid = res.entity
           // Query for lesson and weight using the specific entity ID
           let query = [
             types.Positive(#(types.Val(fact.Ref(eid)), "correction/lesson", types.Var("l"))),
             types.Positive(#(types.Val(fact.Ref(eid)), "correction/weight", types.Var("w"))),
             types.Positive(#(types.Val(fact.Ref(eid)), "correction/id", types.Var("id")))
           ]
           let facts = gleamdb.query(primary, query)
           
           case list.first(facts.rows) {
             Ok(row) -> {
               case dict.get(row, "l"), dict.get(row, "w"), dict.get(row, "id") {
                 Ok(fact.Str(l)), Ok(fact.Float(w)), Ok(fact.Str(id)) -> {
                   Ok(Correction(
                     id: id,
                     vector: [], // Don't need to fetch vector back
                     lesson: l,
                     weight: w,
                     timestamp: 0 
                   ))
                 }
                 _, _, _ -> Error(Nil)
               }
             }
             _ -> Error(Nil)
           }
         }
         _ -> Error(Nil)
       }
    }
    _ -> Error(Nil)
  }
}

pub fn apply_correction(
  current_prob: Float,
  correction: Correction
) -> Float {
  case correction.lesson {
    "invert" -> {
      // Invert the probability relative to 0.5, weighted
      let diff = 0.5 -. current_prob
      current_prob +. diff *. correction.weight
    }
    "veto" -> 0.5 // Reset to uncertainty
    "boost" -> current_prob // Not implemented yet
    _ -> current_prob
  }
}

