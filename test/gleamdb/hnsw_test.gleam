import gleam/int
import gleam/list
import gleam/dict
import gleamdb/fact
import gleamdb/vec_index
import gleeunit/should

pub fn hnsw_layer_test() {
  let idx = vec_index.new()
  
  // 1. Insert 100 vectors with distinct angles to avoid normalization collisions
  // Vector for 'i' is [i, 100 - i, 0]
  let idx = 
    int.range(from: 1, to: 100, with: idx, run: fn(acc, i) {
      let v = [int.to_float(i), int.to_float(100 - i), 0.0]
      vec_index.insert(acc, fact.EntityId(i), v)
    })
  
  // 2. Verify we have multiple layers
  let layer_count = dict.size(idx.layers)
  { layer_count > 1 } |> should.be_true()
  
  // 3. Search for a vector (exactly 50)
  let query = [50.0, 50.0, 0.0]
  let results = vec_index.search(idx, query, 0.99, 1)
  
  { results != [] } |> should.be_true()
  let best = list.first(results) |> should.be_ok()
  best.entity |> should.equal(fact.EntityId(50))
  
  // 4. Delete and verify
  let idx = vec_index.delete(idx, fact.EntityId(50))
  let results_after = vec_index.search(idx, query, 0.99, 1)
  list.any(results_after, fn(r) { r.entity == fact.EntityId(50) }) |> should.be_false()
}
