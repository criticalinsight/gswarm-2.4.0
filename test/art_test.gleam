import gleam/list
import gleamdb/index/art
import gleamdb/fact

pub fn main() {
  test_art_basic_insert_lookup()
  test_art_prefix_conflict()
}

fn test_art_basic_insert_lookup() {
  let tree = art.new()
  let tree = art.insert(tree, fact.Str("apple"), fact.EntityId(1))
  let tree = art.insert(tree, fact.Str("apply"), fact.EntityId(2))
  
  let results = art.lookup(tree, fact.Str("apple"))
  let assert True = list.contains(results, fact.EntityId(1))
  
  let results_y = art.lookup(tree, fact.Str("apply"))
  let assert True = list.contains(results_y, fact.EntityId(2))
  
  let results_none = art.lookup(tree, fact.Str("apply_none"))
  let assert True = list.is_empty(results_none)
}

fn test_art_prefix_conflict() {
  let tree = art.new()
  let tree = art.insert(tree, fact.Str("foo"), fact.EntityId(1))
  let tree = art.insert(tree, fact.Str("foobar"), fact.EntityId(2))
  
  let results = art.lookup(tree, fact.Str("foo"))
  let assert True = list.contains(results, fact.EntityId(1))
  
  let results_long = art.lookup(tree, fact.Str("foobar"))
  let assert True = list.contains(results_long, fact.EntityId(2))
}
