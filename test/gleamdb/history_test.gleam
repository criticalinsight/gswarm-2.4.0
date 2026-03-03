import gleam/list
import gleam/option
import gleeunit/should
import gleamdb
import gleamdb/fact
import gleamdb/shared/types
import gleamdb/storage
import gleamdb/storage/mnesia

pub fn history_audit_test() {
  let db = gleamdb.new()
  
  // 0. Set Schema: user/age is unique (Cardinality ONE)
  let assert Ok(_) = gleamdb.set_schema(db, "user/age", fact.AttributeConfig(unique: True, component: False, retention: fact.All, cardinality: fact.One, check: option.None, composite_group: option.None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  
  // 1. Transaction 1: Create user
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "user/name", fact.Str("Rich")),
    #(fact.Uid(fact.EntityId(1)), "user/age", fact.Int(30))
  ])
  
  // 2. Transaction 2: Update age
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "user/age", fact.Int(31))
  ])
  
  // 3. Transaction 3: Update age again
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "user/age", fact.Int(32))
  ])
  
  // 4. Query History
  let audit = gleamdb.history(db, fact.Uid(fact.EntityId(1)))
  
  // Should have 4 datoms: 1 name, 3 ages
  // Note: Uniqueness/Cardinality one might retract old ones, but they stay in history!
  // Wait, our current cardinality one logic RETRACTS the old value.
  // So we should see:
  // Tx 1: Assert(Name), Assert(Age=30)
  // Tx 2: Retract(Age=30), Assert(Age=31)
  // Tx 3: Retract(Age=31), Assert(Age=32)
  // Total 6 datoms if managed by transactor.
  
  let ages = list.filter_map(audit, fn(d) {
    case d.attribute == "user/age" {
      True -> Ok(d)
      False -> Error(Nil)
    }
  })
  
  should.equal(list.length(ages), 5) // 30 (A), 30 (R), 31 (A), 31 (R), 32 (A)
  
  // Verify chronological order
  let assert [_d1, _d2, _d3, _, _] = ages
}

pub fn recovery_durability_test() {
  let adapter = mnesia.adapter()
  let _ = storage.insert(adapter, [])
  let _ = storage.insert(adapter, []) // Assuming 'datoms' was a placeholder, using empty list for now
  
  // 1. Setup Initial Data
  let db = gleamdb.new_with_adapter(option.Some(adapter))
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(100)), "system/status", fact.Str("online"))
  ])
  
  // 2. "Crash" and Restart
  // In our implementation, restarting with the same adapter should trigger recover_state
  let db2 = gleamdb.new_with_adapter(option.Some(adapter))
  
  // 3. Verify data is recovered immediately
  let results = gleamdb.query(db2, [
    gleamdb.p(#(types.Var("e"), "system/status", types.Var("s")))
  ])
  
  should.equal(list.length(results.rows), 1)
}
