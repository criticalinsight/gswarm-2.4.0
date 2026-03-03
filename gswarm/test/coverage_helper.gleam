import gleam/io
import gleam/list
import gleam/int
import gleam/float
import gleam/string

pub type CoverageResult {
  CoverageResult(module: String, covered: Int, not_covered: Int)
}

@external(erlang, "coverage_ffi", "start")
pub fn start() -> Nil

@external(erlang, "coverage_ffi", "compile")
pub fn compile(dir: String) -> Result(List(String), String)

@external(erlang, "coverage_ffi", "analyze")
fn do_analyze(modules: List(String)) -> List(#(String, Int, Int))

pub fn analyze(modules: List(String)) -> List(CoverageResult) {
  do_analyze(modules)
  |> list.map(fn(res) { CoverageResult(res.0, res.1, res.2) })
}

@external(erlang, "coverage_ffi", "stop")
pub fn stop() -> Nil

pub fn report(results: List(CoverageResult)) {
  let total_covered = list.fold(results, 0, fn(acc, r) { acc + r.covered })
  let total_not_covered = list.fold(results, 0, fn(acc, r) { acc + r.not_covered })
  let total = total_covered + total_not_covered
  
  io.println("\n📊 --- Code Coverage Report ---")
  list.each(results, fn(res) {
    let subtotal = res.covered + res.not_covered
    let pct = case subtotal {
      0 -> 0.0
      _ -> int.to_float(res.covered) /. int.to_float(subtotal) *. 100.0
    }
    
    let color = case pct {
      100.0 -> "🟢"
      _ if pct >. 80.0 -> "🟡"
      _ -> "🔴"
    }
    
    io.println(
      color <> " " <> string.pad_end(res.module, to: 30, with: " ") 
      <> " | " <> float.to_string(pct) <> "% (" 
      <> int.to_string(res.covered) <> "/" <> int.to_string(subtotal) <> " lines)"
    )
  })
  
  let total_pct = case total {
    0 -> 0.0
    _ -> int.to_float(total_covered) /. int.to_float(total) *. 100.0
  }
  
  io.println("--------------------------------")
  io.println("🏆 TOTAL COVERAGE: " <> float.to_string(total_pct) <> "%")
  io.println("--------------------------------\n")
}
