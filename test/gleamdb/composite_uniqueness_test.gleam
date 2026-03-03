import gleeunit/should
import gleamdb
import gleamdb/fact

pub fn composite_uniqueness_test() {
  let db = gleamdb.new()
  
  // 1. Register a composite uniqueness constraint on [user/first, user/last]
  let assert Ok(_) = gleamdb.register_composite(db, ["user/first", "user/last"])
  
  // 2. Transact first entity
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.uid(1), "user/first", fact.Str("Rich")),
    #(fact.uid(1), "user/last", fact.Str("Hickey"))
  ])
  
  // 3. Transact second entity with same values -> Should fail
  let res = gleamdb.transact(db, [
    #(fact.uid(2), "user/first", fact.Str("Rich")),
    #(fact.uid(2), "user/last", fact.Str("Hickey"))
  ])
  
  res |> should.be_error()
  res |> should.equal(Error("Composite uniqueness violation: [\"user/first\", \"user/last\"]"))
}

pub fn composite_missing_attr_test() {
  let db = gleamdb.new()
  
  // 1. Register a composite uniqueness constraint on [user/first, user/last]
  let assert Ok(_) = gleamdb.register_composite(db, ["user/first", "user/last"])
  
  // 2. Transact an entity with ONLY user/first
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.uid(1), "user/first", fact.Str("Rich"))
  ])
  
  // 3. Transact another entity with ONLY user/first (same value)
  // This should SUCCEED because user/last is missing, so the composite check is skipped.
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.uid(2), "user/first", fact.Str("Rich"))
  ])
}

pub fn composite_registration_guard_test() {
  let db = gleamdb.new()
  
  // 1. Transact duplicate composite data BEFORE registration
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.uid(1), "user/first", fact.Str("Stu")),
    #(fact.uid(1), "user/last", fact.Str("Halloway")),
    #(fact.uid(2), "user/first", fact.Str("Stu")),
    #(fact.uid(2), "user/last", fact.Str("Halloway"))
  ])
  
  // 2. Try to register composite -> Should fail
  let res = gleamdb.register_composite(db, ["user/first", "user/last"])
  
  res |> should.be_error()
  res |> should.equal(Error("Existing data violates new composite: [\"user/first\", \"user/last\"]"))
}
