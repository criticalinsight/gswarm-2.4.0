import gleeunit/should
import gleam/option.{None}
import gleam/io
import gleam/int
import gleam/list
import gleamdb
import gleamdb/fact

pub fn retraction_test() {
  io.println("🧪 Testing Recursive Retraction...")
  let assert Ok(db) = gleamdb.start_named("retraction_test_db_unique", None)
  
  // 1. Setup Schema
  let component_config = fact.AttributeConfig(unique: False, component: True, retention: fact.All, cardinality: fact.Many, check: None)
  let assert Ok(_) = gleamdb.set_schema(db, "parent/child", component_config)
  
  // 2. Transact Hierarchical Data
  let p1 = fact.uid(1)
  let c1 = fact.uid(2)
  let g1 = fact.uid(3) // Grandchild
  
  let assert fact.Uid(c1_id) = c1
  let assert fact.Uid(g1_id) = g1
  
  let facts = [
    #(p1, "parent/name", fact.Str("Parent")),
    #(p1, "parent/child", fact.Ref(c1_id)),
    #(c1, "child/name", fact.Str("Child")),
    #(c1, "parent/child", fact.Ref(g1_id)),
    #(g1, "grandchild/name", fact.Str("Grandchild"))
  ]
  
  io.println("📝 Transacting facts...")
  let assert Ok(_final_state) = gleamdb.transact(db, facts)
  
  // Verify existence
  io.println("🔍 Verifying initial state...")
  let h = gleamdb.history(db, p1)
  io.println("📜 History for p1: " <> int.to_string(list.length(h)) <> " datoms")
  list.each(h, fn(d) { io.println("  - " <> d.attribute) })
  
  gleamdb.get_one(db, p1, "parent/name") |> should.equal(Ok(fact.Str("Parent")))
  gleamdb.get_one(db, c1, "child/name") |> should.equal(Ok(fact.Str("Child")))
  gleamdb.get_one(db, g1, "grandchild/name") |> should.equal(Ok(fact.Str("Grandchild")))
  
  // 3. Retrect Parent
  io.println("🗑️ Retracting Parent Entity...")
  let assert Ok(_) = gleamdb.retract_entity(db, p1)
  
  // 4. Verify Recursive Cleanup
  io.println("✨ Verifying cleanup...")
  gleamdb.get_one(db, p1, "parent/name") |> should.be_error()
  gleamdb.get_one(db, c1, "child/name") |> should.be_error()
  gleamdb.get_one(db, g1, "grandchild/name") |> should.be_error()
  io.println("✅ Recursive Retraction Test Passed!")
}
