import gleam/list
import gleamdb/vec_index
import gleamdb/fact

pub fn main() {
  test_hnsw_insertion()
  test_hnsw_search()
}

fn test_hnsw_insertion() {
  let idx = vec_index.new()
  let idx = vec_index.insert(idx, fact.EntityId(1), [0.1, 0.2, 0.3])
  let idx = vec_index.insert(idx, fact.EntityId(2), [0.4, 0.5, 0.6])
  
  // Verify nodes are stored
  let assert True = vec_index.size(idx) == 2
  let assert True = vec_index.contains(idx, fact.EntityId(1))
  let assert True = vec_index.contains(idx, fact.EntityId(2))
}

fn test_hnsw_search() {
  let idx = vec_index.new()
  let points = [
    #(fact.EntityId(1), [1.0, 0.0, 0.0]),
    #(fact.EntityId(2), [0.0, 1.0, 0.0]),
    #(fact.EntityId(3), [0.0, 0.1, 1.0]),
    #(fact.EntityId(4), [0.8, 0.1, 0.0])
  ]
  
  let idx = list.fold(points, idx, fn(acc, p) {
    vec_index.insert(acc, p.0, p.1)
  })
  
  // Search near [1.0, 0.0, 0.0]
  let results = vec_index.search(idx, [0.9, 0.0, 0.0], 0.5, 2)
  
  let assert Ok(best) = list.first(results)
  let assert True = best.entity == fact.EntityId(1)
  let assert True = list.length(results) >= 1
}
