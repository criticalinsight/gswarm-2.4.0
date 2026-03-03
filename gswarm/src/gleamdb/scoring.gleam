import gleam/float
import gleam/list
import gleam/dict
import gleamdb/fact

pub type ScoredResult {
  ScoredResult(entity: fact.EntityId, score: Float)
}

pub type NormalizationStrategy {
  MinMax
  None
}

/// Combines two lists of scored results using weighted union.
/// Scores are first normalized (if requested) then combined by weight.
/// If an entity appears in only one list, it's treated as having score 0.0 in the other.
pub fn weighted_union(
  results_a: List(ScoredResult),
  results_b: List(ScoredResult),
  weight_a: Float,
  weight_b: Float,
  normalization: NormalizationStrategy,
) -> List(ScoredResult) {
  let norm_a = normalize(results_a, normalization)
  let norm_b = normalize(results_b, normalization)
  
  let map_a = list.fold(norm_a, dict.new(), fn(acc, r) {
    dict.insert(acc, r.entity, r.score)
  })
  
  let map_b = list.fold(norm_b, dict.new(), fn(acc, r) {
    dict.insert(acc, r.entity, r.score)
  })
  
  let all_entities = list.append(
    dict.keys(map_a),
    dict.keys(map_b)
  ) |> list.unique()
  
  all_entities
  |> list.map(fn(e) {
    let score_a = case dict.get(map_a, e) {
      Ok(s) -> s
      Error(_) -> 0.0
    }
    let score_b = case dict.get(map_b, e) {
      Ok(s) -> s
      Error(_) -> 0.0
    }
    
    let final_score = weight_a *. score_a +. weight_b *. score_b
    ScoredResult(e, final_score)
  })
  |> list.sort(fn(a, b) {
    float.compare(b.score, a.score)
  })
}

fn normalize(results: List(ScoredResult), strategy: NormalizationStrategy) -> List(ScoredResult) {
  case strategy, results {
    None, _ -> results
    _, [] -> []
    MinMax, _ -> {
      let min_s = list.fold(results, 1000000.0, fn(acc, r) { float.min(acc, r.score) })
      let max_s = list.fold(results, -1000000.0, fn(acc, r) { float.max(acc, r.score) })
      
      let range = max_s -. min_s
      let safe_range = case range {
        0.0 -> 1.0
        val -> val
      }
      
      results
      |> list.map(fn(r) {
        let normalized = {r.score -. min_s} /. safe_range
        ScoredResult(r.entity, normalized)
      })
    }
  }
}
