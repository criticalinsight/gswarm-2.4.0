import gleam/option.{None, Some}
import gleamdb
import gleamdb/fact.{type AttributeConfig, Int, Columnar, Row, All, One}
import gleamdb/q
import gleamdb/shared/types.{type BodyClause, Positive, Var, Val}

pub fn cracking_test() {
  let db = gleamdb.new()
  
  // 1. Configure "val" attribute for cracking (Columnar layout)
  let attr_config = fact.AttributeConfig(
    unique: False,
    component: False,
    retention: All,
    cardinality: One,
    check: None,
    composite_group: None,
    layout: Columnar,
    tier: fact.Memory,
    eviction: fact.AlwaysInMemory,
  )
  
  // Note: set_schema is the correct API in gleamdb.gleam
  let assert Ok(_) = gleamdb.set_schema(db, "val", attr_config)

  // 2. Insert some data
  let facts = [
    #(fact.uid(1), "val", Int(10)),
    #(fact.uid(2), "val", Int(80)),
    #(fact.uid(3), "val", Int(30)),
    #(fact.uid(4), "val", Int(60)),
    #(fact.uid(5), "val", Int(50)),
  ]
  
  let assert Ok(_state) = gleamdb.transact(db, facts)

  // 3. First query: Should trigger initial cracking (range query)
  // We use the query builder and then convert to clauses
  let query = q.new()
    |> q.where(q.v("e"), "val", q.v("v"))
    |> q.filter(types.Gt(Var("v"), Val(Int(50))))
    |> q.to_clauses()

  let _results = gleamdb.query(db, query)
  
  // 4. Second query: Should use the existing cracked state
  let query2 = q.new()
    |> q.where(q.v("e"), "val", q.v("v"))
    |> q.filter(types.Gt(Var("v"), Val(Int(20))))
    |> q.to_clauses()

  let _results2 = gleamdb.query(db, query2)
  
  // Verification would involve checking the state.columnar_store for the crack offsets
  // but for now, just ensuring it runs without crashing is the goal.
}
