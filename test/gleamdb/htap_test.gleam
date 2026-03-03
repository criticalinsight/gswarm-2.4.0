import gleeunit/should
import gleamdb
import gleamdb/fact
import gleamdb/q
import gleamdb/shared/types
import gleam/option.{None, Some}
import gleam/list
import gleam/dict

pub fn columnar_aggregate_test() {
  let db = gleamdb.new()
  
  // 1. Setup Columnar Schema
  let config = fact.AttributeConfig(
    unique: False,
    component: False,
    retention: fact.All,
    cardinality: fact.Many,
    check: None,
    composite_group: None,
    layout: fact.Columnar,
    tier: fact.Memory,
    eviction: fact.AlwaysInMemory,
  )
  let assert Ok(_) = gleamdb.set_schema(db, "sensor/reading", config)
  
  // 2. Transact data
  let readings = [10, 20, 30, 40, 50]
  let facts = list.map(readings, fn(v) {
    #(fact.uid(1), "sensor/reading", fact.Int(v))
  })
  let assert Ok(_) = gleamdb.transact(db, facts)
  
  // 3. Run Optimized Aggregate (Sum)
  // Query: ?sum_val = sum("sensor/reading")
  let query = q.new()
    |> q.sum("sum_val", "sensor/reading", [])
    |> q.to_clauses()
    
  let results = gleamdb.query(db, query)
  
  // Verify results
  results.rows |> list.length() |> should.equal(1)
  let assert [row] = results.rows
  dict.get(row, "sum_val") |> should.equal(Ok(fact.Float(150.0)))
  
  // 4. Run Optimized Aggregate (Avg)
  let query_avg = q.new()
    |> q.avg("avg_val", "sensor/reading", [])
    |> q.to_clauses()
    
  let results_avg = gleamdb.query(db, query_avg)
  let assert [row_avg] = results_avg.rows
  dict.get(row_avg, "avg_val") |> should.equal(Ok(fact.Float(30.0)))
}

pub fn mixed_layout_test() {
  let db = gleamdb.new()
  
  // Columnar
  let col_config = fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None, composite_group: None, layout: fact.Columnar, tier: fact.Memory, eviction: fact.AlwaysInMemory)
  let assert Ok(_) = gleamdb.set_schema(db, "val_col", col_config)
  
  // Row (Default)
  let row_config = fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory)
  let assert Ok(_) = gleamdb.set_schema(db, "val_row", row_config)
  
  let facts = [
    #(fact.uid(1), "val_col", fact.Int(100)),
    #(fact.uid(1), "val_row", fact.Int(50)),
  ]
  let assert Ok(_) = gleamdb.transact(db, facts)
  
  // Query both
  let query = q.new()
    |> q.where(q.v("e"), "val_col", q.v("v1"))
    |> q.where(q.v("e"), "val_row", q.v("v2"))
    |> q.to_clauses()
    
  let results = gleamdb.query(db, query)
  results.rows |> list.length() |> should.equal(1)
  let assert [row] = results.rows
  dict.get(row, "v1") |> should.equal(Ok(fact.Int(100)))
  dict.get(row, "v2") |> should.equal(Ok(fact.Int(50)))
}
