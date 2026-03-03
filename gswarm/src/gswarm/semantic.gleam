import gleam/list
import gleam/string
import gleam/int


fn range(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}


pub fn generate_embedding(text: String) -> List(Float) {
  // Keep text embedding for text queries, but improve mock
  let hash = text_to_hash(text, 0)
  range(1, 16) |> list.map(fn(i) { int_to_float(hash + i) /. 100.0 })
}

fn text_to_hash(text: String, acc: Int) -> Int {
  case text {
    "" -> acc
    _ -> {
       // Simple hash
       acc + string.length(text)
    }
  }
}

fn int_to_float(i: Int) -> Float {
  int.to_float(i)
}
