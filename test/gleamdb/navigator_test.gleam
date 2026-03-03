import gleam/list
import gleamdb/q
import gleamdb/shared/types.{Positive, Var, Val}
import gleamdb/engine/navigator
import gleamdb/fact.{Str}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn reorder_test() {
  // Broad scan first in input: [?e "age" ?a] [?e "name" "Alice"]
  let clauses = q.new()
    |> q.where(q.v("e"), "age", q.v("a"))
    |> q.where(q.v("e"), "name", q.s("Alice"))
    |> q.to_clauses()
    
  let planned = navigator.plan(clauses)
  
  // Alice constant is more selective, should be moved to the front.
  case planned {
    [Positive(#(Var("e"), "name", Val(Str("Alice")))), Positive(#(Var("e"), "age", Var("a")))] -> {
      should.be_true(True)
    }
    _ -> should.fail()
  }
}

pub fn control_clause_stability_test() {
  // Control clauses should stay at the end
  let clauses = q.new()
    |> q.where(q.v("e"), "age", q.v("a"))
    |> q.limit(10)
    |> q.where(q.v("e"), "name", q.s("Alice"))
    |> q.to_clauses()
    
  let planned = navigator.plan(clauses)
  
  case list.last(planned) {
    Ok(types.Limit(10)) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn explain_test() {
  let clauses = q.new()
    |> q.where(q.v("e"), "name", q.s("Alice"))
    |> q.to_clauses()
    
  let output = navigator.explain(clauses)
  // Should contains "Query Plan" and "Positive"
  should.be_true(output != "") // Just check it runs without panic and returns something
}
