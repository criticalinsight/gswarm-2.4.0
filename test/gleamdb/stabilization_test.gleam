import gleeunit/should
import gleamdb
import gleamdb/fact
import gleamdb/q
import gleamdb/shared/utils
import gleamdb/shared/types
import gleam/list
import gleam/dict
import gleam/int
import gleam/option.{Some, None}

pub fn ordered_sequence_test() {
  let db = gleamdb.new()
  
  // Transact facts in a specific order
  let facts = [
    #(fact.Uid(fact.EntityId(1)), "order", fact.Int(1)),
    #(fact.Uid(fact.EntityId(1)), "order", fact.Int(2)),
    #(fact.Uid(fact.EntityId(1)), "order", fact.Int(3)),
  ]
  
  let assert Ok(state) = gleamdb.transact(db, facts)
  
  // Verify tx_index is assigned correctly
  let history = gleamdb.history(db, fact.Uid(fact.EntityId(1)))
    |> list.filter(fn(d: fact.Datom) { d.attribute == "order" })
    |> list.sort(fn(a: fact.Datom, b: fact.Datom) { int.compare(a.tx_index, b.tx_index) })
  
  let indices = list.map(history, fn(d: fact.Datom) { d.tx_index })
  indices |> should.equal([0, 1, 2])
  
  let values = list.map(history, fn(d: fact.Datom) { d.value })
  values |> should.equal([fact.Int(1), fact.Int(2), fact.Int(3)])
}

pub fn fuzzy_json_test() {
  let noisy = "Some text before {\"key\": \"value\", \"nested\": {\"a\": 1}} some text after"
  utils.extract_json(noisy) |> should.equal("{\"key\": \"value\", \"nested\": {\"a\": 1}}")
  
  let complex = "Debug: { \"msg\": \"hello } world\" } Done."
  utils.extract_json(complex) |> should.equal("{ \"msg\": \"hello } world\" }")
}

pub fn filtered_pull_test() {
  let db = gleamdb.new()
  let facts = [
    #(fact.Uid(fact.EntityId(1)), "name", fact.Str("Hero")),
    #(fact.Uid(fact.EntityId(1)), "type", fact.Str("section")),
    #(fact.Uid(fact.EntityId(2)), "name", fact.Str("Post 1")),
    #(fact.Uid(fact.EntityId(2)), "type", fact.Str("content")),
  ]
  let assert Ok(_) = gleamdb.transact(db, facts)
  
  let query = q.new()
    |> q.where(q.v("e"), "type", q.s("section"))
    |> q.pull("data", q.v("e"), [types.Wildcard])
    |> q.to_clauses()
    
  let results = gleamdb.query(db, query)
  results.rows |> list.length() |> should.equal(1)
  
  let row = list.first(results.rows) |> should.be_ok()
  let data = dict.get(row, "data") |> should.be_ok()
  
  case data {
    fact.Map(m) -> {
      dict.get(m, "name") |> should.equal(Ok(fact.Str("Hero")))
      dict.get(m, "type") |> should.equal(Ok(fact.Str("section")))
    }
    _ -> should.fail()
  }
}

pub fn composite_uniqueness_test() {
  let db = gleamdb.new()
  
  // Define schema with composite group
  let config = fact.AttributeConfig(
    unique: False,
    component: False,
    retention: fact.All,
    cardinality: fact.One,
    check: None,
    composite_group: Some("slug_unique"),
    layout: fact.Row,
    tier: fact.Memory,
    eviction: fact.AlwaysInMemory,
  )
  
  let assert Ok(_) = gleamdb.set_schema(db, "slug", config)
  let assert Ok(_) = gleamdb.set_schema(db, "site_id", config)
  
  // Transact first pair
  let facts1 = [
    #(fact.Uid(fact.EntityId(10)), "slug", fact.Str("home")),
    #(fact.Uid(fact.EntityId(10)), "site_id", fact.Int(100)),
  ]
  let assert Ok(_) = gleamdb.transact(db, facts1)
  
  // Transact same slug but different site_id (Should be OK)
  let facts2 = [
    #(fact.Uid(fact.EntityId(20)), "slug", fact.Str("home")),
    #(fact.Uid(fact.EntityId(20)), "site_id", fact.Int(101)),
  ]
  let assert Ok(_) = gleamdb.transact(db, facts2)
  
  // Transact same slug and same site_id (Should FAIL)
  let facts3 = [
    #(fact.Uid(fact.EntityId(30)), "slug", fact.Str("home")),
    #(fact.Uid(fact.EntityId(30)), "site_id", fact.Int(100)),
  ]
  let result = gleamdb.transact(db, facts3)
  result |> should.be_error()
}
