import gleam/list
import gleeunit
import gleeunit/should
import gleamdb/fact
import gleamdb/index/bm25
import gleamdb/scoring

pub fn main() {
  gleeunit.main()
}

// Helper to create test datoms
fn create_text_datom(entity: Int, text: String) -> fact.Datom {
  fact.Datom(
    entity: fact.EntityId(entity),
    attribute: "msg/content",
    value: fact.Str(text),
    tx: 100,
    tx_index: 0,
    valid_time: 2147483647,
    operation: fact.Assert,
  )
}

pub fn bm25_index_test() {
  let datoms = [
    create_text_datom(1, "hello world"),
    create_text_datom(2, "hello gleam"),
    create_text_datom(3, "gleam is awesome"),
  ]

  let index = bm25.build(datoms, "msg/content")

  // Check stats
  index.doc_count |> should.equal(3)
  
  // "hello" appears in 1 and 2
  {bm25.score(index, fact.EntityId(1), "hello", 1.2, 0.75) >. 0.0} |> should.equal(True)
  {bm25.score(index, fact.EntityId(2), "hello", 1.2, 0.75) >. 0.0} |> should.equal(True)
  
  // "gleam" appears in 2 and 3
  {bm25.score(index, fact.EntityId(2), "gleam", 1.2, 0.75) >. 0.0} |> should.equal(True)
  {bm25.score(index, fact.EntityId(3), "gleam", 1.2, 0.75) >. 0.0} |> should.equal(True)
  
  // "world" appears only in 1 -> higher score for 1 than for "hello" (higher IDF)
  let s1_world = bm25.score(index, fact.EntityId(1), "world", 1.2, 0.75)
  let s1_hello = bm25.score(index, fact.EntityId(1), "hello", 1.2, 0.75)
  {s1_world >. s1_hello} |> should.equal(True)
  
  // "missing" appears nowhere
  bm25.score(index, fact.EntityId(1), "missing", 1.2, 0.75) |> should.equal(0.0)
}

pub fn weighted_union_test() {
  let r1 = scoring.ScoredResult(fact.EntityId(1), 1.0) // Norm: 1.0
  let r2 = scoring.ScoredResult(fact.EntityId(2), 0.5) // Norm: 0.0
  let res_a = [r1, r2]
  
  let r3 = scoring.ScoredResult(fact.EntityId(2), 1.0) // Norm: 1.0
  let r4 = scoring.ScoredResult(fact.EntityId(3), 0.5) // Norm: 0.0
  let res_b = [r3, r4]
  
  // Entity 2: 
  // List A: raw 0.5 -> norm 0.0 (min in A)
  // List B: raw 1.0 -> norm 1.0 (max in B)
  // Weights: 0.5, 0.5
  // Combined: 0.5*0.0 + 0.5*1.0 = 0.5
  
  // Entity 1:
  // List A: raw 1.0 -> norm 1.0
  // List B: missing -> 0.0
  // Combined: 0.5*1.0 + 0.0 = 0.5
  
  let combined = scoring.weighted_union(res_a, res_b, 0.5, 0.5, scoring.MinMax)
  
  // Sort order checks
  // Let's calculate expected:
  // E1: A=1.0, B=0.0 -> 0.5
  // E2: A=0.0, B=1.0 -> 0.5
  // E3: A=0.0, B=0.0 -> 0.0
  
  list.length(combined) |> should.equal(3)
  
  let assert Ok(first) = list.first(combined)
  first.score |> should.equal(0.5)
}
