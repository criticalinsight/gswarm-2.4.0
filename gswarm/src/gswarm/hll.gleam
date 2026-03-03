import gleam/int
import gleam/float
import gleam/dict.{type Dict}
import gleam/result

/// HyperLogLog for cardinality estimation.
/// Standard error: ~1.04 / sqrt(m), where m = 2^precision.
pub type HLL {
  HLL(
    registers: Dict(Int, Int),
    precision: Int,
    m: Int
  )
}

/// Create a new HyperLogLog with specified precision (4 to 16).
pub fn new(precision: Int) -> HLL {
  let m =
    int.range(from: 1, to: precision, with: 1, run: fn(acc, _) { acc * 2 })
  HLL(registers: dict.new(), precision: precision, m: m)
}

/// Insert a key into the HyperLogLog.
pub fn insert(hll: HLL, key: String) -> HLL {
  let hash = phash2(key, 4_294_967_296) // 32-bit range
  let index = hash % hll.m
  let w = hash / hll.m
  let rho = rho_value(w)
  
  let current = case dict.get(hll.registers, index) {
    Ok(v) -> v
    Error(_) -> 0
  }
  
  case rho > current {
    True -> HLL(..hll, registers: dict.insert(hll.registers, index, rho))
    False -> hll
  }
}

/// Estimate cardinality.
pub fn estimate(hll: HLL) -> Int {
  let alpha = case hll.m {
    16 -> 0.673
    32 -> 0.697
    64 -> 0.709
    _ -> 0.7213 /. { 1.0 +. 1.079 /. int.to_float(hll.m) }
  }
  
  let normalized_sum =
    int.range(from: 0, to: hll.m - 1, with: 0.0, run: fn(acc, i) {
      let register_val = case dict.get(hll.registers, i) {
        Ok(v) -> v
        Error(_) -> 0
      }
      acc
      +. {
        1.0
        /. {
          float.power(2.0, int.to_float(register_val)) |> result.unwrap(1.0)
        }
      }
    })
  
  let inverse_sum = case normalized_sum {
    0.0 -> 0.0
    val -> 1.0 /. val
  }
  
  let raw_estimate = alpha *. int.to_float(hll.m * hll.m) *. inverse_sum
  
  case raw_estimate <=. 2.5 *. int.to_float(hll.m) {
    True -> {
      let v = hll.m - dict.size(hll.registers)
      case v {
        0 -> float.round(raw_estimate)
        _ -> {
          // LinearCounting: m * ln(m/V)
          let m_float = int.to_float(hll.m)
          let v_float = int.to_float(v)
          let val = m_float *. { float.logarithm(m_float /. v_float) |> result.unwrap(0.0) }
          float.round(val)
        }
      }
    }
    False -> float.round(raw_estimate)
  }
}

/// Calculate the position of the leftmost 1-bit.
fn rho_value(val: Int) -> Int {
  case val <= 0 {
    True -> 32
    False -> {
      // Simplistic rho for Gleam (find first set bit)
      // In production we'd use bit manipulation efficiently
      find_rho(val, 1)
    }
  }
}

fn find_rho(val: Int, count: Int) -> Int {
  case val % 2 == 1 || count >= 32 {
    True -> count
    False -> find_rho(val / 2, count + 1)
  }
}

@external(erlang, "erlang", "phash2")
fn phash2(x: a, range: Int) -> Int
