import gleeunit/should
import gleam/option.{None}
import gleam/list
import gleamdb
import gleamdb/fact
import gleamdb/shared/types.{Out, In}

pub fn graph_traversal_test() {
  let assert Ok(db) = gleamdb.start_named("graph_traverse_db", None)
  
  let _ = gleamdb.set_schema(db, "user/name", fact.AttributeConfig(
    unique: False, component: False, retention: fact.All, cardinality: fact.One, 
    check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory
  ))
  let _ = gleamdb.set_schema(db, "user/friends", fact.AttributeConfig(
    unique: False, component: False, retention: fact.All, cardinality: fact.Many, 
    check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory
  ))
  let _ = gleamdb.set_schema(db, "user/posts", fact.AttributeConfig(
    unique: False, component: False, retention: fact.All, cardinality: fact.Many, 
    check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory
  ))

  // User 1 -> Friends [2, 3] -> Posts [10, 20]
  // Entity 1
  let f1 = #(fact.uid(1), "user/name", fact.Str("Alice"))
  let f2 = #(fact.uid(1), "user/friends", fact.Ref(fact.ref(2)))
  let f3 = #(fact.uid(1), "user/friends", fact.Ref(fact.ref(3)))
  
  // Entity 2
  let f4 = #(fact.uid(2), "user/name", fact.Str("Bob"))
  let f5 = #(fact.uid(2), "user/posts", fact.Ref(fact.ref(10)))
  
  // Entity 3
  let f6 = #(fact.uid(3), "user/name", fact.Str("Charlie"))
  let f7 = #(fact.uid(3), "user/posts", fact.Ref(fact.ref(20)))

  // Entity 4 (Someone who likes Post 20)
  let f8 = #(fact.uid(4), "user/name", fact.Str("Dave"))
  let f9 = #(fact.uid(4), "likes/post", fact.Ref(fact.ref(20)))
  
  let assert Ok(_) = gleamdb.transact(db, [f1, f2, f3, f4, f5, f6, f7, f8, f9])
  
  // 1. One hop: Alice's friends
  let assert Ok(friends) = gleamdb.traverse(db, fact.uid(1), [Out("user/friends")], 5)
  list.length(friends) |> should.equal(2)
  
  // 2. Two hops: Alice's friends' posts
  let assert Ok(posts) = gleamdb.traverse(db, fact.uid(1), [Out("user/friends"), Out("user/posts")], 5)
  list.length(posts) |> should.equal(2) // Post 10 and 20
  
  // 3. Three hops: Alice's friends' posts likers (Traversal mixed Out/In)
  let assert Ok(likers) = gleamdb.traverse(db, fact.uid(1), [Out("user/friends"), Out("user/posts"), In("likes/post")], 5)
  list.length(likers) |> should.equal(1) // Just Dave (Entity 4)

  // 4. Max Depth Limit Rejection
  let res_err = gleamdb.traverse(db, fact.uid(1), [Out("a"), Out("b"), Out("c")], 2)
  res_err |> should.be_error()
}
