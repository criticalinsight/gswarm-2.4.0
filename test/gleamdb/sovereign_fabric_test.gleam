import gleeunit/should
import gleam/dict
import gleam/list
import gleamdb.{p}
import gleam/option
import gleamdb/fact
import gleamdb/shared/types.{Wildcard, Nested, PullMap, PullSingle}

pub fn sovereign_fabric_test() {
  let db = gleamdb.new()
  
  // 1. Setup Schema for components
  let assert Ok(_) = gleamdb.set_schema(db, "user/name", fact.AttributeConfig(unique: True, component: False, retention: fact.All, cardinality: fact.One, check: option.None, composite_group: option.None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  let assert Ok(_) = gleamdb.set_schema(db, "user/profile", fact.AttributeConfig(unique: False, component: True, retention: fact.All, cardinality: fact.One, check: option.None, composite_group: option.None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  let assert Ok(_) = gleamdb.set_schema(db, "profile/bio", fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.One, check: option.None, composite_group: option.None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  
  // 2. Transact initial state (TX 1)
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "user/name", fact.Str("Rich")),
    #(fact.Uid(fact.EntityId(1)), "user/profile", fact.Int(2)),
    #(fact.Uid(fact.EntityId(2)), "profile/bio", fact.Str("Composer of Code"))
  ])
  
  // 3. Verify Pull API (Nested)
  let pull_pattern = [Nested("user/profile", [Wildcard])]
  let result = gleamdb.pull(db, fact.Uid(fact.EntityId(1)), pull_pattern)
  
  let assert PullMap(res_map) = result
  
  let profile_map = case dict.get(res_map, "user/profile") {
    Ok(PullMap(m)) -> m
    _ -> panic as "Failed to pull nested profile"
  }
  
  dict.get(profile_map, "profile/bio")
  |> should.equal(Ok(PullSingle(fact.Str("Composer of Code"))))
  
  // 4. Update state (TX 2)
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "user/name", fact.Str("Rich Hickey"))
  ])
  
  // 5. Verify Bi-temporality (as_of)
  let q = [p(#(types.Var("e"), "user/name", types.Var("name")))]
  
  // Current state
  let current_res = gleamdb.query(db, q)
  let assert Ok(binding) = list.first(current_res.rows)
  should.equal(dict.get(binding, "name"), Ok(fact.Str("Rich Hickey")))

  // Historical state (TX 1)
  let historic_res = gleamdb.as_of(db, 1, q)
  let assert Ok(h_binding) = list.first(historic_res.rows)
  should.equal(dict.get(h_binding, "name"), Ok(fact.Str("Rich")))
  
  // 6. Verify Component Cascades (Recursive Retraction)
  let assert Ok(_) = gleamdb.retract(db, [
    #(fact.Uid(fact.EntityId(1)), "user/name", fact.Str("Rich Hickey")),
    #(fact.Uid(fact.EntityId(1)), "user/profile", fact.Int(2))
  ])
  
  // Verify user is gone
  gleamdb.query(db, q).rows
  |> should.equal([])
  
  // Verify profile (component) was also retracted automatically
  let q_profile = [p(#(types.Var("e"), "profile/bio", types.Var("bio")))]
  gleamdb.query(db, q_profile).rows
  |> should.equal([])
}
