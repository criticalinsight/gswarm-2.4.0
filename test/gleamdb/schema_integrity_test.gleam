import gleeunit/should
import gleam/option.{None, Some}
import gleam/dict
import gleam/list
import gleamdb
import gleamdb/fact.{AttributeConfig, One, Many, All, LatestOnly, Uid, EntityId, Int, Str}
import gleamdb/shared/types

pub fn cardinality_one_test() {
  let db = gleamdb.new()
  
  // Set schema to Cardinality ONE
  let assert Ok(_) = gleamdb.set_schema(db, "user/email", AttributeConfig(
    unique: False, 
    component: False, 
    retention: All, 
    cardinality: One, 
    check: None,
    composite_group: None,
    layout: fact.Row,
    tier: fact.Memory,
    eviction: fact.AlwaysInMemory,
  ))
  
  let eid = Uid(EntityId(1))
  
  // Assert first email
  let assert Ok(_) = gleamdb.transact(db, [#(eid, "user/email", Str("first@example.com"))])
  
  // Assert second email (should replace first)
  let assert Ok(_) = gleamdb.transact(db, [#(eid, "user/email", Str("second@example.com"))])
  
  // Pull current emails
  // Correct pattern usage: pull_attr returns List(PullItem)
  let result = gleamdb.pull(db, eid, gleamdb.pull_attr("user/email"))
  
  // Should only have the second one
  case result {
    types.PullMap(m) -> {
      case dict.get(m, "user/email") {
        Ok(types.PullSingle(Str("second@example.com"))) -> should.be_true(True)
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn cardinality_many_test() {
  let db = gleamdb.new()
  
  // Set schema to Cardinality MANY
  let assert Ok(_) = gleamdb.set_schema(db, "user/role", AttributeConfig(
    unique: False, 
    component: False, 
    retention: All, 
    cardinality: Many, 
    check: None,
    composite_group: None,
    layout: fact.Row,
    tier: fact.Memory,
    eviction: fact.AlwaysInMemory,
  ))
  
  let eid = Uid(EntityId(1))
  
  let assert Ok(_) = gleamdb.transact(db, [#(eid, "user/role", Str("admin"))])
  let assert Ok(_) = gleamdb.transact(db, [#(eid, "user/role", Str("editor"))])
  
  let result = gleamdb.pull(db, eid, gleamdb.pull_attr("user/role"))
  case result {
    types.PullMap(m) -> {
      case dict.get(m, "user/role") {
        Ok(types.PullMany(roles)) -> list.length(roles) |> should.equal(2)
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn check_constraint_test() {
  let db = gleamdb.new()
  
  // Register a predicate
  gleamdb.register_predicate(db, "is_positive", fn(val) {
    case val {
      Int(i) -> i > 0
      _ -> False
    }
  })
  
  // Set schema with CHECK constraint
  let assert Ok(_) = gleamdb.set_schema(db, "user/age", AttributeConfig(
    unique: False, 
    component: False, 
    retention: All, 
    cardinality: One, 
    check: Some("is_positive"),
    composite_group: None,
    layout: fact.Row,
    tier: fact.Memory,
    eviction: fact.AlwaysInMemory,
  ))
  
  let eid = Uid(EntityId(1))
  
  // Assert valid age
  let assert Ok(_) = gleamdb.transact(db, [#(eid, "user/age", Int(25))])
  
  // Assert invalid age (should fail)
  let result = gleamdb.transact(db, [#(eid, "user/age", Int(-5))])
  should.be_error(result)
}

pub fn latest_only_retention_test() {
  let db = gleamdb.new()
  
  // Set schema with LatestOnly retention
  let assert Ok(_) = gleamdb.set_schema(db, "system/status", AttributeConfig(
    unique: False, 
    component: False, 
    retention: LatestOnly, 
    cardinality: One, 
    check: None,
    composite_group: None,
    layout: fact.Row,
    tier: fact.Memory,
    eviction: fact.AlwaysInMemory,
  ))
  
  let eid = Uid(EntityId(1))
  
  let assert Ok(_) = gleamdb.transact(db, [#(eid, "system/status", Str("starting"))])
  let assert Ok(_) = gleamdb.transact(db, [#(eid, "system/status", Str("running"))])
  
  // Pull history directly from engine to see datoms
  let history = gleamdb.history(db, eid) |> list.filter(fn(d) { d.attribute == "system/status" })
  
  // With LatestOnly, the index prunes historical asserts.
  list.length(history) |> should.equal(1)
  case history {
    [fact.Datom(_, _, Str("running"), _, _, _, fact.Assert)] -> should.be_true(True)
    _ -> should.fail()
  }
}
