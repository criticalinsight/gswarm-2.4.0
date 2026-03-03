import gleam/option.{None}
import gleeunit/should
import gleamdb
import gleamdb/fact

pub fn schema_guard_uniqueness_test() {
  let db = gleamdb.new()
  
  // 1. Transact duplicate data for a non-unique attribute
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.uid(1), "user/email", fact.Str("rich@hickey.com")),
    #(fact.uid(2), "user/email", fact.Str("rich@hickey.com"))
  ])
  
  // 2. Try to make "user/email" unique -> Should fail
  let config = fact.AttributeConfig(unique: True, component: False, retention: fact.All, cardinality: fact.Many, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory)
  let res = gleamdb.set_schema(db, "user/email", config)
  
  res |> should.be_error()
  res |> should.equal(Error("Cannot make non-unique attribute unique: existing data has duplicates"))
}

pub fn schema_guard_cardinality_test() {
  let db = gleamdb.new()
  
  // 1. Transact multiple values for an entity's attribute
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.uid(1), "user/alias", fact.Str("Rich")),
    #(fact.uid(1), "user/alias", fact.Str("Hickey"))
  ])
  
  // 2. Try to set cardinality to ONE -> Should fail
  let config = fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.One, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory)
  let res = gleamdb.set_schema(db, "user/alias", config)
  
  res |> should.be_error()
  res |> should.equal(Error("Cannot set cardinality to ONE: existing entities have multiple values"))
}

pub fn schema_guard_success_test() {
  let db = gleamdb.new()
  
  // 1. Transact unique data
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.uid(1), "user/email", fact.Str("rich@hickey.com")),
    #(fact.uid(2), "user/email", fact.Str("stu@arthur.com"))
  ])
  
  // 2. Make it unique -> Should succeed
  let config = fact.AttributeConfig(unique: True, component: False, retention: fact.All, cardinality: fact.Many, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory)
  let assert Ok(_) = gleamdb.set_schema(db, "user/email", config)
  
  // 3. Subsequent duplicates should be rejected
  let res = gleamdb.transact(db, [
    #(fact.uid(3), "user/email", fact.Str("rich@hickey.com"))
  ])
  res |> should.be_error()
}
