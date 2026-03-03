import gleam/dict
import gleamdb
import gleamdb/fact.{Int, Str}
import gleamdb/shared/types.{Wildcard, Attr, Nested, PullMap, PullSingle}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn pull_api_test() {
  let db = gleamdb.new()
  
  // Setup data: Alice (1) is 30, Bob (2) is her friend
  let assert Ok(_) = gleamdb.transact(db, [
    #(fact.Uid(fact.EntityId(1)), "name", Str("Alice")),
    #(fact.Uid(fact.EntityId(1)), "age", Int(30)),
    #(fact.Uid(fact.EntityId(2)), "name", Str("Bob")),
    #(fact.Uid(fact.EntityId(1)), "friend", Int(2)),
  ])
  
  // 1. Pull all attributes for Alice
  let res1 = gleamdb.pull(db, fact.Uid(fact.EntityId(1)), [Wildcard])
  let assert PullMap(d1) = res1
  should.equal(dict.get(d1, "name"), Ok(PullSingle(Str("Alice"))))
  should.equal(dict.get(d1, "age"), Ok(PullSingle(Int(30))))
  
  // 2. Pull selective attributes
  let res2 = gleamdb.pull(db, fact.Uid(fact.EntityId(1)), [Attr("name")])
  let assert PullMap(d2) = res2
  should.equal(dict.get(d2, "name"), Ok(PullSingle(Str("Alice"))))
  should.equal(dict.get(d2, "age"), Error(Nil))
  
  // 3. Pull nested friend
  let res3 = gleamdb.pull(db, fact.Uid(fact.EntityId(1)), [Nested("friend", [Wildcard])])
  let assert PullMap(d3) = res3
  let assert Ok(PullMap(friend_map)) = dict.get(d3, "friend")
  should.equal(dict.get(friend_map, "name"), Ok(PullSingle(Str("Bob"))))
  
  // 4. Mixed pattern
  let res4 = gleamdb.pull(db, fact.Uid(fact.EntityId(1)), [
    Attr("age"),
    Nested("friend", [Attr("name")])
  ])
  let assert PullMap(d4) = res4
  should.equal(dict.get(d4, "age"), Ok(PullSingle(Int(30))))
  let assert Ok(PullMap(fm)) = dict.get(d4, "friend")
  should.equal(dict.get(fm, "name"), Ok(PullSingle(Str("Bob"))))
}
