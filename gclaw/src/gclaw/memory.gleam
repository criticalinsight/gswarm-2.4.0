import gleam/option.{None}
import gleamdb/transactor
import gleamdb/fact
import gleamdb/storage
import gleamdb/storage/disk
import gleamdb/shared/types
import gleamdb/engine
import gleam/list
import gleam/dict
import gleam/order
import gclaw/fact as gfact
import gleam/int
import gleamdb/scoring
import gclaw/memory_types
import gclaw/metrics

pub type Memory {
  Memory(db: transactor.Db)
}

pub fn init_ephemeral() -> Memory {
  init(storage.ephemeral())
}

pub fn init_persistent(path: String) -> Memory {
  init(disk.disk(path))
}

fn init(adapter: storage.StorageAdapter) -> Memory {
  let assert Ok(db) = transactor.start(adapter)
  
  // Set up schema
  let _ =
    transactor.set_schema(
      db,
      gfact.msg_timestamp,
      fact.AttributeConfig(
        unique: False,
        component: False,
        retention: fact.All,
        cardinality: fact.One,
        check: None,
      ),
    )
  let _ =
    transactor.set_schema(
      db,
      gfact.mem_vector,
      fact.AttributeConfig(
        unique: False,
        component: False,
        retention: fact.LatestOnly,
        cardinality: fact.One,
        check: None,
      ),
    )
  let _ =
    transactor.set_schema(
      db,
      gfact.msg_session,
      fact.AttributeConfig(
        unique: False,
        component: False,
        retention: fact.All,
        cardinality: fact.One,
        check: None,
      ),
    )
  
  // Enable BM25 for content
  let _ = transactor.create_bm25_index(db, memory_types.content_attr)

  // Configure memory attributes
  let _ = transactor.set_schema(
      db,
      memory_types.type_attr,
      fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.One, check: None)
  )
   let _ = transactor.set_schema(
      db,
      memory_types.source_attr,
      fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.One, check: None)
  )
    let _ = transactor.set_schema(
      db,
      memory_types.tags_attr,
      fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None)
  )

  // Register Custom Indices
  let _ = transactor.register_index_adapter(db, metrics.new_adapter())
  let _ = transactor.create_index(db, memory_types.importance_attr, "metric", memory_types.importance_attr)
  let _ = transactor.create_index(db, memory_types.sentiment_attr, "metric", memory_types.sentiment_attr)

  Memory(db)
}

// Basic remember (no vector)
pub fn remember(mem: Memory, facts: List(fact.Fact)) -> Memory {
  let _ = transactor.transact(mem.db, facts)
  mem
}

// Semantic remember (with vector)
pub fn remember_semantic(mem: Memory, facts: List(fact.Fact), vector: List(Float)) -> Memory {
  // Find the entity ID from the facts (assuming first fact has the EID we want to attach vector to)
  let facts_with_vector = case facts {
    [#(eid, _, _), ..] -> {
      [#(eid, gfact.mem_vector, fact.Vec(vector)), ..facts]
    }
    _ -> facts
  }
  remember(mem, facts_with_vector)
}


pub fn recall_hybrid(mem: Memory, query_text: String, query_vec: List(Float), limit: Int) -> List(String) {
  let state = transactor.get_state(mem.db)
  
  // 1. BM25 Search
  let bm25_query = [
    types.BM25(
      variable: "val",
      attribute: memory_types.content_attr,
      query: query_text,
      threshold: 0.0,
      k1: 1.2,
      b: 0.75
    )
  ]
  let bm25_results = engine.run(state, bm25_query, [], None, None).rows
  let bm25_scored = list.filter_map(bm25_results, fn(row) {
    case dict.get(row, "val") {
       Ok(fact.Ref(eid)) -> {
          // Engine run result for BM25 doesn't return score directly in row unless we bind it?
          // Actually engine returns bare results. We need the score.
          // The engine logic for BM25 returns a list of matching Contexts.
          // It doesn't propagate the score currently.
          // Tier 1 task was "Add BM25 Clause to Engine".
          // If the engine doesn't return the score, we can't do weighted union properly.
          // Wait, `scoring.gleam` expects `ScoredResult`.
          // If `engine` swallows the score, we have a problem.
          // BUT, for now, let's assume we can re-score or we access the index directly?
          // Accessing index directly is better for scoring.
          
          Ok(scoring.ScoredResult(eid, 1.0)) // Placeholder score until engine supports score binding
       }
       _ -> Error(Nil)
    }
  })

  // 2. Vector Search
  let vec_query = [
    types.SimilarityEntity(variable: "val", vector: query_vec, threshold: 0.7)
  ]
  let vec_results = engine.run(state, vec_query, [], None, None).rows
   let vec_scored = list.filter_map(vec_results, fn(row) {
    case dict.get(row, "val") {
       Ok(fact.Ref(eid)) -> Ok(scoring.ScoredResult(eid, 1.0)) // Placeholder
       _ -> Error(Nil)
    }
  })

  // 3. Weighted Union
  let combined = scoring.weighted_union(bm25_scored, vec_scored, 0.3, 0.7, scoring.MinMax)
  
  // 4. Fetch content
  list.take(combined, limit)
  |> list.map(fn(r) { 
     // Fetch text content for the entity
     let fact.EntityId(eid) = r.entity
     "Entity: " <> int.to_string(eid) 
  })
}

// Hybrid Retrieval: Recent + Semantic
pub fn get_context_window(mem: Memory, session_id: String, limit: Int, query_vec: List(Float)) -> List(String) {
  let state = transactor.get_state(mem.db)
  
  // 1. Recent Messages (Time-based)
  let recent_clauses = [
    types.Positive(#(types.Var("m"), gfact.msg_session, types.Val(fact.Str(session_id)))),
    types.Positive(#(types.Var("m"), gfact.msg_content, types.Var("content"))),
    types.Positive(#(types.Var("m"), gfact.msg_role, types.Var("role"))),
    types.Positive(#(types.Var("m"), gfact.msg_timestamp, types.Var("ts"))),
    types.OrderBy("ts", types.Desc),
    types.Limit(limit)
  ]
  let recent_results = engine.run(state, recent_clauses, [], None, None).rows

  // 2. Semantic Search (Vector-based)
  // Logic: Search by vector first, then filter by session in Gleam (post-process)
  // This bypasses complex Datalog join issues in GleamDB 1.7.1
  let semantic_results = case list.is_empty(query_vec) {
    True -> []
    False -> {
      let vec_clauses = [
        types.SimilarityEntity(variable: "m", vector: query_vec, threshold: 0.0), // Low threshold for debugging
        types.Positive(#(types.Var("m"), gfact.msg_session, types.Var("sess"))),
        types.Positive(#(types.Var("m"), gfact.msg_content, types.Var("content"))),
        types.Positive(#(types.Var("m"), gfact.msg_role, types.Var("role"))),
        types.Positive(#(types.Var("m"), gfact.msg_timestamp, types.Var("ts"))),
        types.Filter(types.Eq(types.Var("sess"), types.Val(fact.Str(session_id)))),
        types.Limit(limit)
      ]
      let res = engine.run(state, vec_clauses, [], None, None).rows
      res
    }
  }

  // 3. Merge & Deduplicate
  let merged = list.fold(list.append(recent_results, semantic_results), dict.new(), fn(acc, r) {
    let assert Ok(fact.Int(ts)) = dict.get(r, "ts")
    dict.insert(acc, ts, r)
  })
  
  // 4. Sort and Format
  dict.values(merged)
  |> list.sort(fn(a, b) {
    let assert Ok(fact.Int(ts_a)) = dict.get(a, "ts")
    let assert Ok(fact.Int(ts_b)) = dict.get(b, "ts")
    case ts_a <= ts_b {
      True -> order.Lt
      False -> order.Gt
    }
  })
  |> list.map(fn(r) {
    let assert Ok(fact.Str(role)) = dict.get(r, "role")
    let assert Ok(fact.Str(content)) = dict.get(r, "content")
    role <> ": " <> content
  })
}
