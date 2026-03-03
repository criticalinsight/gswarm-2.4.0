import gleeunit/should
import gleam/list
import gleam/int
import gleamdb
import gleamdb/fact
import gleamdb/q

pub fn expected_morsel_test() {
  // 1. Initialize DB
  let db = gleamdb.new()
  
  // 2. Ingest Dataset
  let data = list.range(1, 250)
    |> list.flat_map(fn(i) {
      let eid = fact.deterministic_uid(i)
      [#(eid, "item/type", fact.Str("parallel_item"))]
    })
  let assert Ok(_) = gleamdb.transact(db, data)
  
  // 3. Run Query
  let query = q.new()
    |> q.where(q.v("e"), "item/type", q.v("parallel_item"))
    |> q.to_clauses()
    
  let results = gleamdb.query(db, query)
  
  // Verify 250 items were correctly map-reduced across chunks
  results.rows |> list.length() |> should.equal(250)
}
