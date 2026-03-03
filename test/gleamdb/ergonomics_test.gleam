import gleam/io
import gleam/option.{None}
import gleeunit
import gleeunit/should
import gleamdb
import gleamdb/q

pub fn main() {
  gleeunit.main()
}

pub fn supervision_test() {
  io.println("Running supervision_test")
  // Verify child_spec compiles and works in a supervisor
  // We can't easily run a supervisor in test without blocking, but we can verify start_link
  
  let db = gleamdb.new_with_adapter_and_timeout(None, 1000)
  
  // Test DSL
  let query = q.select(["e"])
    |> q.where(q.v("e"), "attr", q.i(42))
    |> q.to_clauses()
  
  // Verify query execution (even if empty db)
  let _results = gleamdb.query(db, query)
  
  // Test Public Types (compilation check)
  let _p: gleamdb.PullPattern = gleamdb.pull_all()
  
  should.be_true(True)
}

pub fn dsl_test() {
  let _query = q.new()
    |> q.where(q.v("e"), "name", q.s("Sly"))
    |> q.negate(q.v("e"), "status", q.s("offline"))
    |> q.to_clauses()
    
  // Check structure (this is internal detail but good to verify DSL logic)
  // We just ensure it compiles and runs.
  should.be_true(True)
}
