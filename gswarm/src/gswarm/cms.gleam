import gleam/dict.{type Dict}
import gleam/int

/// A Count-Min Sketch for frequency estimation.
/// Space complexity: O(width * depth)
/// Bias: Always overestimates (Count-Min)
pub type CMS {
  CMS(table: Dict(#(Int, Int), Int), width: Int, depth: Int)
}

/// Create a new CMS with specified dimensions.
pub fn new(width: Int, depth: Int) -> CMS {
  CMS(table: dict.new(), width: width, depth: depth)
}

/// Increment the count for a key in the sketch.
pub fn increment(sketch: CMS, key: String) -> CMS {
  int.range(from: 0, to: sketch.depth - 1, with: sketch, run: fn(acc, row) {
    let col = phash2(#(key, row), acc.width)
    let current = case dict.get(acc.table, #(row, col)) {
      Ok(c) -> c
      Error(_) -> 0
    }
    CMS(..acc, table: dict.insert(acc.table, #(row, col), current + 1))
  })
}

/// Estimate the frequency of a key.
/// Returns the minimum count across all rows (guaranteed upper bound).
pub fn estimate(sketch: CMS, key: String) -> Int {
  int.range(
    from: 0,
    to: sketch.depth - 1,
    with: 2_147_483_647,
    run: fn(min_val, row) {
      let col = phash2(#(key, row), sketch.width)
      let count = case dict.get(sketch.table, #(row, col)) {
        Ok(c) -> c
        Error(_) -> 0
      }
      case count < min_val {
        True -> count
        False -> min_val
      }
    },
  )
}

@external(erlang, "erlang", "phash2")
fn phash2(x: a, range: Int) -> Int
