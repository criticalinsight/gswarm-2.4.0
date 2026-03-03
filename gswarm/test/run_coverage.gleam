import coverage_helper
import gleam/io
import gleam/int
import gleam/list
import gleam/string
import gleam/result

pub type Atom
pub type Encoding { Utf8 }
pub type ReportModuleName { GleeunitProgress }
pub type GleeunitProgressOption { Colored(Bool) }
pub type EunitOption {
  Verbose
  NoTty
  Report(#(ReportModuleName, List(GleeunitProgressOption)))
  ScaleTimeouts(Int)
}

@external(erlang, "erlang", "binary_to_atom")
fn binary_to_atom(a: String, b: Encoding) -> Atom

@external(erlang, "gleeunit_ffi", "find_files")
fn find_files(matching matching: String, in in: String) -> List(String)

@external(erlang, "gleeunit_ffi", "run_eunit")
fn run_eunit(a: List(Atom), b: List(EunitOption)) -> Result(Nil, Nil)

fn gleam_to_erlang_module_name(path: String) -> String {
  case string.ends_with(path, ".gleam") {
    True -> path |> string.replace(".gleam", "") |> string.replace("/", "@")
    False -> path |> string.split("/") |> list.last |> result.unwrap(path) |> string.replace(".erl", "")
  }
}

pub fn main() {
  io.println("🚀 Starting Coverage Analysis for Gswarm...")
  coverage_helper.start()
  
  let ebin = "build/dev/erlang/gswarm/ebin"
  
  case coverage_helper.compile(ebin) {
    Ok(modules) -> {
      io.println("✅ Instrumented " <> int.to_string(list.length(modules)) <> " modules.")
      
      let options = [Verbose, NoTty, Report(#(GleeunitProgress, [Colored(True)])), ScaleTimeouts(10)]
      let modules_to_test = 
        find_files(matching: "**/*.{erl,gleam}", in: "test")
        |> list.map(gleam_to_erlang_module_name)
        |> list.map(binary_to_atom(_, Utf8))
      
      let _ = run_eunit(modules_to_test, options)
      
      let results = coverage_helper.analyze(modules)
      coverage_helper.report(results)
    }
    Error(e) -> io.println("❌ Coverage Error: " <> e)
  }
  
  coverage_helper.stop()
}
