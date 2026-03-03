import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/bit_array
import gleam/string
import gleamdb/fact

/// A functional Adaptive Radix Tree (ART) node.
/// Uses path compression to minimize depth for sparse keys.
pub type Node {
  Node(
    prefix: BitArray,
    children: Dict(Int, Node),
    values: List(fact.EntityId),
  )
}

pub type Art {
  Art(root: Node)
}

/// Create a new empty ART index.
pub fn new() -> Art {
  Art(root: Node(prefix: <<>>, children: dict.new(), values: []))
}

/// Insert an entity ID into the tree for a given fact value.
pub fn insert(tree: Art, key: fact.Value, entity: fact.EntityId) -> Art {
  let key_bytes = value_to_bytes(key)
  Art(root: do_insert(tree.root, key_bytes, entity))
}

fn do_insert(node: Node, key: BitArray, entity: fact.EntityId) -> Node {
  case key {
    <<>> -> Node(..node, values: [entity, ..node.values])
    _ -> {
      // Find common prefix
      let #(common, rest_node, rest_key) = split_common_prefix(node.prefix, key)
      
      case rest_node {
        <<>> -> {
          // Node prefix matches part of key, continue down children
          case rest_key {
            <<first:8, tail:bits>> -> {
              let child = case dict.get(node.children, first) {
                Ok(c) -> c
                Error(Nil) -> Node(prefix: tail, children: dict.new(), values: [entity])
              }
              let updated_child = case dict.get(node.children, first) {
                Ok(_) -> do_insert(child, tail, entity)
                Error(Nil) -> child
              }
              Node(..node, children: dict.insert(node.children, first, updated_child))
            }
            _ -> Node(..node, values: [entity, ..node.values])
          }
        }
        _ -> {
          // Divergence - split this node
          let assert <<first_node:8, tail_node:bits>> = rest_node
          let old_node = Node(..node, prefix: tail_node)

          case rest_key {
            <<first_key:8, tail_key:bits>> -> {
              let new_leaf =
                Node(prefix: tail_key, children: dict.new(), values: [entity])
              Node(
                prefix: common,
                children: dict.from_list([
                  #(first_node, old_node),
                  #(first_key, new_leaf),
                ]),
                values: [],
              )
            }
            _ -> {
              // New key is a prefix of old node's remaining prefix
              Node(
                prefix: common,
                children: dict.from_list([#(first_node, old_node)]),
                values: [entity],
              )
            }
          }
        }
      }
    }
  }
}

/// Lookup all entities associated with a value.
pub fn lookup(tree: Art, key: fact.Value) -> List(fact.EntityId) {
  let key_bytes = value_to_bytes(key)
  do_lookup(tree.root, key_bytes)
}

fn do_lookup(node: Node, key: BitArray) -> List(fact.EntityId) {
  let #(_common, rest_node, rest_key) = split_common_prefix(node.prefix, key)
  
  case rest_node {
    <<>> -> {
      case rest_key {
        <<first:8, tail:bits>> -> {
          case dict.get(node.children, first) {
            Ok(child) -> do_lookup(child, tail)
            Error(Nil) -> []
          }
        }
        _ -> node.values
      }
    }
    _ -> [] // Prefix mismatch
  }
}

fn split_common_prefix(p1: BitArray, p2: BitArray) -> #(BitArray, BitArray, BitArray) {
  do_split_prefix(p1, p2, <<>>)
}

fn do_split_prefix(p1: BitArray, p2: BitArray, acc: BitArray) -> #(BitArray, BitArray, BitArray) {
  case p1, p2 {
    <<b1:8, t1:bits>>, <<b2:8, t2:bits>> if b1 == b2 -> {
      do_split_prefix(t1, t2, <<acc:bits, b1:8>>)
    }
    _, _ -> #(acc, p1, p2)
  }
}

fn value_to_bytes(v: fact.Value) -> BitArray {
  case v {
    fact.Int(i) -> <<0:8, i:64>>
    fact.Float(f) -> <<1:8, f:float-64>>
    fact.Str(s) -> <<2:8, s:utf8>>
    fact.Ref(fact.EntityId(id)) -> <<3:8, id:64>>
    fact.Bool(True) -> <<4:8, 1:8>>
    fact.Bool(False) -> <<4:8, 0:8>>
    fact.Vec(l) -> {
      let bytes = list.fold(l, <<>>, fn(acc, f) { <<acc:bits, f:float-64>> })
      <<5:8, bytes:bits>>
    }
    fact.List(l) -> {
      let bytes = list.fold(l, <<>>, fn(acc, val) { <<acc:bits, { value_to_bytes(val) }:bits>> })
      <<6:8, bytes:bits>>
    }
    fact.Map(m) -> {
      let bytes = dict.fold(m, <<>>, fn(acc, k, v) {
        let k_bits = <<k:utf8>>
        <<acc:bits, {string.length(k)}:32, k_bits:bits, {value_to_bytes(v)}:bits>>
      })
      <<7:8, {dict.size(m)}:32, bytes:bits>>
    }
    fact.Blob(b) -> <<8:8, b:bits>>
  }
}

pub fn bytes_to_value(b: BitArray) -> Option(fact.Value) {
  case b {
    <<0:8, i:64>> -> Some(fact.Int(i))
    <<1:8, f:float-64>> -> Some(fact.Float(f))
    <<2:8, rest:bits>> -> {
      case bit_array.to_string(rest) {
        Ok(s) -> Some(fact.Str(s))
        Error(_) -> None
      }
    }
    <<3:8, id:64>> -> Some(fact.Ref(fact.EntityId(id)))
    <<4:8, 1:8>> -> Some(fact.Bool(True))
    <<4:8, 0:8>> -> Some(fact.Bool(False))
    <<8:8, b:bits>> -> Some(fact.Blob(b))
    // Vec, List, and Map are harder to reconstruct without length prefix, skipping for now as we only need Str for StartsWith
    _ -> None
  }
}

/// Remove an entity ID from the tree for a given fact value.
pub fn delete(tree: Art, key: fact.Value, entity: fact.EntityId) -> Art {
  let key_bytes = value_to_bytes(key)
  Art(root: do_delete(tree.root, key_bytes, entity))
}

fn do_delete(node: Node, key: BitArray, entity: fact.EntityId) -> Node {
  case key {
    <<>> -> Node(..node, values: list.filter(node.values, fn(e) { e != entity }))
    _ -> {
      let #(_common, rest_node, rest_key) = split_common_prefix(node.prefix, key)
      
      case rest_node {
        <<>> -> {
          // Node prefix matches part of key
          case rest_key {
            <<first:8, tail:bits>> -> {
              case dict.get(node.children, first) {
                Ok(child) -> {
                  let updated_child = do_delete(child, tail, entity)
                  Node(..node, children: dict.insert(node.children, first, updated_child))
                }
                Error(Nil) -> node // Path doesn't exist, nothing to delete
              }
            }
            _ -> Node(..node, values: list.filter(node.values, fn(e) { e != entity }))
          }
        }
        _ -> node // Prefix mismatch, nothing to delete
      }
    }
  }
}

/// Search for all entities where the indexed value starts with the given prefix.
/// Returns the Value and EntityId.
pub fn search_prefix_entries(tree: Art, prefix: String) -> List(#(fact.Value, fact.EntityId)) {
  let prefix_bytes = <<2:8, prefix:utf8>>
  do_search_prefix_entries(tree.root, prefix_bytes, <<>>)
}

fn do_search_prefix_entries(node: Node, search_prefix: BitArray, path_acc: BitArray) -> List(#(fact.Value, fact.EntityId)) {
  case search_prefix {
    <<>> -> collect_all_entries(node, path_acc)
    _ -> {
      let #(_common, rest_node, rest_search) = split_common_prefix(node.prefix, search_prefix)
      
      // The current node contributes `node.prefix` to the path
      // But we might be in the middle of `node.prefix`.
      // Actually, standard ART recursion:
      
      case rest_node {
        <<>> -> {
          // Node prefix matches start of search prefix. 
          // Path so far is `path_acc <> node.prefix`.
          let current_path = <<path_acc:bits, {node.prefix}:bits>>
          
          case rest_search {
            <<first:8, tail:bits>> -> {
              case dict.get(node.children, first) {
                Ok(child) -> do_search_prefix_entries(child, tail, <<current_path:bits, first:8>>)
                Error(Nil) -> []
              }
            }
            <<>> -> collect_all_entries(node, path_acc)
            _ -> []
          }
        }
        _ -> {
          // Mismatch or divergence.
          // If rest_search is empty, we found a match (the search prefix is a prefix of this node's path)
          case rest_search {
            <<>> -> {
               // The search prefix ended, but we are inside `node.prefix`.
               // All values in this node (and children) match!
               // But wait, we need to reconstruct the FULL keys.
               // The key for this node's values is `path_acc <> node.prefix`.
               // The logic `collect_all_entries` handles the subtree.
               // We just call it with the full path to this node.
               // `path_acc` is what came from parent.
               collect_all_entries(node, path_acc)
            }
            _ -> []
          }
        }
      }
    }
  }
}

fn collect_all_entries(node: Node, path_acc: BitArray) -> List(#(fact.Value, fact.EntityId)) {
  let current_key_bytes = <<path_acc:bits, {node.prefix}:bits>>
  
  // 1. Current node values
  let current_entries = case bytes_to_value(current_key_bytes) {
    Some(val) -> list.map(node.values, fn(eid) { #(val, eid) })
    None -> [] // Should not happen for valid stored strings
  }
  
  // 2. Children values
  let children_entries = 
    dict.to_list(node.children)
    |> list.flat_map(fn(pair) {
      let #(byte, child) = pair
      collect_all_entries(child, <<current_key_bytes:bits, byte:8>>)
    })
    
  list.append(current_entries, children_entries)
}
pub fn search_prefix(tree: Art, prefix: String) -> List(fact.EntityId) {
  let prefix_bytes = <<2:8, prefix:utf8>>
  do_search_prefix(tree.root, prefix_bytes)
}

fn do_search_prefix(node: Node, prefix: BitArray) -> List(fact.EntityId) {
  case prefix {
    <<>> -> collect_all_values(node)
    _ -> {
      let #(_common, rest_node, rest_prefix) = split_common_prefix(node.prefix, prefix)
      
      case rest_node {
        <<>> -> {
          // Node prefix matches the start of the search prefix
          case rest_prefix {
            <<first:8, tail:bits>> -> {
              case dict.get(node.children, first) {
                Ok(child) -> do_search_prefix(child, tail)
                Error(Nil) -> []
              }
            }
            <<>> -> collect_all_values(node) // Exact match on node prefix
            _ -> [] // Should be covered by first case but safe fallback
          }
        }
        _ -> {
          // Node prefix is longer than or diverges from the remaining search prefix.
          // If the remaining search prefix is empty, then this node and all its children match.
          // If search prefix is not empty, then we have a mismatch.
          case rest_prefix {
            <<>> -> collect_all_values(node)
            _ -> []
          }
        }
      }
    }
  }
}

fn collect_all_values(node: Node) -> List(fact.EntityId) {
  let child_values =
    dict.values(node.children)
    |> list.flat_map(collect_all_values)
  
  list.append(node.values, child_values)
}
