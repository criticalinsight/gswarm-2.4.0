import gleam/list
import gleam/float

pub fn dot_product(v1: List(Float), v2: List(Float)) -> Float {
  do_dot_product(v1, v2, 0.0)
}

fn do_dot_product(v1: List(Float), v2: List(Float), acc: Float) -> Float {
  case v1, v2 {
    [x, ..xs], [y, ..ys] -> do_dot_product(xs, ys, acc +. { x *. y })
    _, _ -> acc
  }
}

pub fn magnitude(v: List(Float)) -> Float {
  let sum_sq = list.fold(v, 0.0, fn(acc, x) { acc +. { x *. x } })
  case float.square_root(sum_sq) {
    Ok(m) -> m
    Error(_) -> 0.0
  }
}

pub fn cosine_similarity(v1: List(Float), v2: List(Float)) -> Float {
  let mag1 = magnitude(v1)
  let mag2 = magnitude(v2)
  
  case mag1 == 0.0 || mag2 == 0.0 {
    True -> 0.0
    False -> dot_product(v1, v2) /. { mag1 *. mag2 }
  }
}

/// L2 (Euclidean) distance between two vectors.
pub fn euclidean_distance(v1: List(Float), v2: List(Float)) -> Float {
  let sum_sq = list.zip(v1, v2)
    |> list.fold(0.0, fn(acc, pair) {
      let diff = pair.0 -. pair.1
      acc +. { diff *. diff }
    })
  case float.square_root(sum_sq) {
    Ok(d) -> d
    Error(_) -> 0.0
  }
}

/// Normalize a vector to unit length.
pub fn normalize(v: List(Float)) -> List(Float) {
  let mag = magnitude(v)
  case mag == 0.0 {
    True -> v
    False -> list.map(v, fn(x) { x /. mag })
  }
}

/// Number of dimensions.
pub fn dimensions(v: List(Float)) -> Int {
  list.length(v)
}
