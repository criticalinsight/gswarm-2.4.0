import gleam/list
import gleam/float

/// Calculate the cosine similarity between two vectors.
/// Result is between -1.0 and 1.0.
/// Returns Error if vectors have different lengths or depend on 0 magnitude.
pub fn cosine_similarity(a: List(Float), b: List(Float)) -> Result(Float, Nil) {
  let len_a = list.length(a)
  let len_b = list.length(b)
  
  case len_a == len_b {
    False -> Error(Nil)
    True -> {
      let dot_product = dot(a, b)
      let mag_a = magnitude(a)
      let mag_b = magnitude(b)
      
      case mag_a == 0.0 || mag_b == 0.0 {
        True -> Error(Nil)
        False -> Ok(dot_product /. { mag_a *. mag_b })
      }
    }
  }
}

fn dot(a: List(Float), b: List(Float)) -> Float {
  list.zip(a, b)
  |> list.fold(0.0, fn(acc, pair) {
    let #(x, y) = pair
    acc +. { x *. y }
  })
}

fn magnitude(v: List(Float)) -> Float {
  let sum_sq = list.fold(v, 0.0, fn(acc, x) { acc +. { x *. x } })
  let assert Ok(res) = float.square_root(sum_sq)
  res
}
