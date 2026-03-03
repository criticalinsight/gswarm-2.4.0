import gleeunit/should
import gleam/list
import gleamdb
import gleamdb/fact
import gleamdb/shared/types.{Var, Val, Positive, Filter, And, Or, Eq, Gt}

pub fn jit_lite_complex_filter_test() {
  let db = gleamdb.new()

  // Ingest data
  let data = list.range(1, 100)
    |> list.flat_map(fn(i) {
      let eid = fact.deterministic_uid(i)
      [
        #(eid, "item/type", fact.Str("product")),
        #(eid, "item/price", fact.Int(i)),
        #(eid, "item/active", fact.Bool(i % 2 == 0))
      ]
    })
  
  let assert Ok(_) = gleamdb.transact(db, data)

  // JIT-Lite compiled predicate test
  // ?type == "product" AND (?price > 50 AND ?active == true) OR ?price == 10
  
  let filter_expr = Or(
    And(
      Eq(Var("type"), Val(fact.Str("product"))),
      And(
        Gt(Var("price"), Val(fact.Int(50))),
        Eq(Var("active"), Val(fact.Bool(True)))
      )
    ),
    Eq(Var("price"), Val(fact.Int(10)))
  )

  let q = [
    Positive(#(Var("e"), "item/type", Var("type"))),
    Positive(#(Var("e"), "item/price", Var("price"))),
    Positive(#(Var("e"), "item/active", Var("active"))),
    Filter(filter_expr)
  ]

  let results = gleamdb.query(db, q)

  // Prices > 50 that are even (active), plus 10 (which is even)
  // Even prices > 50: 52, 54, 56, ... 100 = 25 items
  // Plus price == 10: + 1 item
  // Total expected = 26 items
  
  list.length(results.rows) |> should.equal(26)
}
