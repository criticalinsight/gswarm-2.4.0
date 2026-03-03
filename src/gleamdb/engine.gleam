import gleam/dict.{type Dict}
import gleam/list
import gleam/set.{type Set}
import gleam/result
import gleam/option.{type Option, None, Some}
import gleamdb/algo/bloom
import gleam/int
import gleam/float
import gleam/string
import gleam/order
import gleamdb/fact
import gleamdb/vector
import gleamdb/vec_index
import gleamdb/shared/types
import gleamdb/index
import gleamdb/algo/graph
import gleamdb/algo/aggregate
import gleamdb/index/ets
import gleamdb/index/ets as ets_index
import gleam/erlang/process
import gleamdb/algo/vectorized
import gleamdb/algo/cracking
import gleamdb/engine/navigator
import gleamdb/engine/morsel
import gleamdb/index/art

// Rule moved to types.gleam to avoid cycle

// Pull types moved to shared/types.gleam to avoid cycles

pub fn run(
  db_state: types.DbState,
  clauses: List(types.BodyClause),
  rules: List(types.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> types.QueryResult {
  let as_of_v = case as_of_valid {
    Some(vt) -> Some(vt)
    None -> Some(2_147_483_647) // Max Int (v1.9.0 default: inclusive of future valid time)
  }
  let all_rules = list.append(rules, db_state.stored_rules)
  let all_derived = derive_all_facts(db_state, all_rules, as_of_tx, as_of_v)
  let initial_context = [dict.new()]
  
  // Logical Navigator: Plan the query before execution
  let planned_clauses = navigator.plan(clauses)
  
  // [Dogfood Learning] Graph Type Safety: check if graph edges are Refs
  list.each(planned_clauses, fn(c) {
    case c {
      types.PageRank(_, edge, _, _, _) | types.CycleDetect(edge, _) | 
      types.StronglyConnectedComponents(edge, _, _) | types.TopologicalSort(edge, _, _) -> {
        let config = dict.get(db_state.schema, edge)
        case config {
          Ok(conf) if conf.cardinality != fact.Many -> {
             // In a real logger we'd use that, for now print to stdout
             // which is visible in Gswarm logs
             let _ = gleamdb_io_println("⚠️ Warning: Graph edge '" <> edge <> "' should be Ref(EntityId) for optimal performance.")
          }
          _ -> Nil
        }
      }
      _ -> Nil
    }
  })

  let #(rows, store) = list.fold(planned_clauses, #(initial_context, None), fn(acc, clause) {
    let #(contexts, current_store) = acc
    case clause {
      types.Limit(n) -> #(list.take(contexts, n), current_store)
      types.Offset(n) -> #(list.drop(contexts, n), current_store)
      types.OrderBy(var, dir) -> {
        let sorted = list.sort(contexts, fn(a, b) {
          let val_a = dict.get(a, var) |> result.unwrap(fact.Int(0))
          let val_b = dict.get(b, var) |> result.unwrap(fact.Int(0))
          let ord = compare_values(val_a, val_b)
          case dir {
            types.Asc -> ord
            types.Desc -> case ord {
              order.Lt -> order.Gt
              order.Gt -> order.Lt
              order.Eq -> order.Eq
            }
          }
        })
        #(sorted, current_store)
      }
      types.GroupBy(_) -> #(contexts, current_store)
      types.Filter(expr) -> {
         // JIT-Lite: Compile the predicate once per query clause execution
         let compiled_pred = compile_predicate(expr)
         let next_contexts = list.filter(contexts, fn(ctx) { compiled_pred(ctx) })
         #(next_contexts, current_store)
      }
      normal_clause -> {
        let #(next_contexts, next_store) = list.fold(contexts, #([], current_store), fn(inner_acc, ctx) {
          let #(acc_ctxs, acc_store) = inner_acc
          let #(new_ctxs, clause_store) = solve_clause_with_derived(db_state, normal_clause, ctx, all_derived, as_of_tx, as_of_v)
          let merged_store = merge_optional_stores(acc_store, clause_store)
          #(list.append(acc_ctxs, new_ctxs), merged_store)
        })
        #(next_contexts, next_store)
      }
    }
  })

  let aggregates = list.fold(planned_clauses, dict.new(), fn(acc, clause) {
    case clause {
      types.Aggregate(var, func, _, _) -> dict.insert(acc, var, func)
      _ -> acc
    }
  })

  types.QueryResult(
    rows: rows |> list.unique(),
    metadata: types.QueryMetadata(
      tx_id: as_of_tx,
      valid_time: as_of_valid,
      execution_time_ms: 0, // Placeholder
      shard_id: None,
      aggregates: aggregates,
    ),
    updated_columnar_store: store,
  )
}

@external(erlang, "io", "format")
fn gleamdb_io_println(x: String) -> Nil

fn derive_all_facts(db_state: types.DbState, rules: List(types.Rule), as_of_tx: Option(Int), as_of_valid: Option(Int)) -> Set(fact.Datom) {
  do_derive(db_state, rules, as_of_tx, as_of_valid, set.new())
}

fn do_derive(
  db_state: types.DbState,
  rules: List(types.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  derived: Set(fact.Datom),
) -> Set(fact.Datom) {
  let initial_new = derived
  do_derive_recursive(db_state, rules, as_of_tx, as_of_valid, derived, initial_new, True)
}

fn do_derive_recursive(
  db_state: types.DbState,
  rules: List(types.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  all_derived: Set(fact.Datom),
  last_new_derived: Set(fact.Datom),
  first_run: Bool,
) -> Set(fact.Datom) {
  case !first_run && set.size(last_new_derived) == 0 {
    True -> all_derived
    False -> {
      let next_new = list.fold(rules, set.new(), fn(acc, r) {
        // Semi-Naive Evaluation:
        // For each rule, we only want results that involve at least one fact 
        // from 'last_new_derived'. This avoids re-discovering the same facts.
        let #(results, _store) = solve_rule_body_semi_naive(db_state, r.body, all_derived, last_new_derived, as_of_tx, as_of_valid)
        
        list.fold(results, acc, fn(inner_acc, ctx) {
          let e = resolve_part_optional(r.head.0, ctx)
          let v = resolve_part_optional(r.head.2, ctx)
          case e, v {
            Some(fact.Ref(fact.EntityId(eid_val))), Some(val) -> {
              let d = fact.Datom(entity: fact.EntityId(eid_val), attribute: r.head.1, value: val, tx: 0, tx_index: 0, valid_time: 0, operation: fact.Assert)
              case set.contains(all_derived, d) {
                True -> inner_acc
                False -> set.insert(inner_acc, d)
              }
            }
            Some(fact.Int(eid_val)), Some(val) -> {
              let d = fact.Datom(entity: fact.EntityId(eid_val), attribute: r.head.1, value: val, tx: 0, tx_index: 0, valid_time: 0, operation: fact.Assert)
              case set.contains(all_derived, d) {
                True -> inner_acc
                False -> set.insert(inner_acc, d)
              }
            }
            _, _ -> inner_acc
          }
        })
      })

      case set.size(next_new) == 0 {
        True -> all_derived
        False -> {
          let next_all = set.union(all_derived, next_new)
          do_derive_recursive(db_state, rules, as_of_tx, as_of_valid, next_all, next_new, False)
        }
      }
    }
  }
}

fn solve_rule_body_semi_naive(
  db_state: types.DbState,
  body: List(types.BodyClause),
  all_derived: Set(fact.Datom),
  _delta: Set(fact.Datom),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(List(Dict(String, fact.Value)), Option(Dict(String, List(fact.ColumnChunk)))) {
  list.fold(body, #([dict.new()], None), fn(acc, clause_i) {
    let #(ctxs, current_store) = acc
    list.fold(ctxs, #([], current_store), fn(inner_acc, ctx) {
      let #(acc_ctxs, acc_store) = inner_acc
      let #(new_ctxs, clause_store) = solve_clause_with_derived(db_state, clause_i, ctx, all_derived, as_of_tx, as_of_valid)
      #(list.append(acc_ctxs, new_ctxs), merge_optional_stores(acc_store, clause_store))
    })
  })
}

fn merge_optional_stores(
  s1: Option(Dict(String, List(fact.ColumnChunk))),
  s2: Option(Dict(String, List(fact.ColumnChunk))),
) -> Option(Dict(String, List(fact.ColumnChunk))) {
  case s1, s2 {
    Some(m1), Some(m2) -> Some(dict.merge(m1, m2))
    Some(_), None -> s1
    None, Some(_) -> s2
    None, None -> None
  }
}

fn solve_bloom_join(
  db_state: types.DbState,
  _variable: String,
  clauses: List(types.BodyClause),
  ctx: Dict(String, fact.Value),
  rules: List(types.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(List(Dict(String, fact.Value)), Option(Dict(String, List(fact.ColumnChunk)))) {
  // Simple implementation for now to restore build
  list.fold(clauses, #([ctx], None), fn(acc, c) {
    let #(contexts, current_store) = acc
    list.fold(contexts, #([], current_store), fn(inner_acc, inner_ctx) {
       let #(acc_ctxs, acc_store) = inner_acc
       let #(new_ctxs, clause_store) = solve_clause(db_state, c, inner_ctx, rules, as_of_tx, as_of_valid)
       #(list.append(acc_ctxs, new_ctxs), merge_optional_stores(acc_store, clause_store))
    })
  })
}

fn solve_clause(
  db_state: types.DbState,
  clause: types.BodyClause,
  ctx: Dict(String, fact.Value),
  rules: List(types.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(List(Dict(String, fact.Value)), Option(Dict(String, List(fact.ColumnChunk)))) {
  case clause {
    types.Positive(c) -> {
      let #(res, store) = solve_positive_with_state(db_state, c, ctx, as_of_tx, as_of_valid)
      #(res, store)
    }
    types.Negative(c) -> #(solve_negative(db_state, c, ctx, as_of_tx, as_of_valid), None)
    types.Aggregate(var, func, target, filter_clauses) -> {
      solve_aggregate(ctx, var, func, target, db_state, filter_clauses, rules, as_of_tx, as_of_valid)
    }
    types.Similarity(variable: var, vector: vec, threshold: threshold) ->
      #(solve_similarity(db_state, var, vec, threshold, ctx, as_of_tx, as_of_valid), None)
    types.SimilarityEntity(variable: var, vector: vec, threshold: threshold) ->
      #(solve_similarity_entity(db_state, var, vec, threshold, ctx, as_of_tx, as_of_valid), None)
    types.CustomIndex(variable: var, index_name: name, query: q, threshold: t) ->
      #(solve_custom_index(db_state, var, name, q, t, ctx), None)
    types.Filter(expr) -> {
      let compiled_pred = compile_predicate(expr)
      case compiled_pred(ctx) {
        True -> #([ctx], None)
        False -> #([], None)
      }
    }
    types.Bind(var, f) -> {
      let val = f(ctx)
      #([dict.insert(ctx, var, val)], None)
    }
    types.Temporal(var, entity, attr, start, end, basis) -> 
      #(solve_temporal(db_state, var, entity, attr, start, end, basis, ctx), None)
    types.ShortestPath(from, to, edge, path_var, cost_var) -> 
      #(solve_shortest_path(db_state, from, to, edge, path_var, cost_var, ctx), None)
    types.PageRank(entity_var, edge, rank_var, d, iter) -> 
      #(solve_pagerank(db_state, entity_var, edge, rank_var, d, iter, ctx), None)
    types.Virtual(pred, args, outputs) -> 
      #(solve_virtual(db_state, pred, args, outputs, ctx), None)
    types.Reachable(from, edge, node_var) -> 
      #(solve_reachable(db_state, from, edge, node_var, ctx), None)
    types.ConnectedComponents(edge, entity_var, component_var) -> 
      #(solve_connected_components(db_state, edge, entity_var, component_var, ctx), None)
    types.Neighbors(from, edge, depth, node_var) -> 
      #(solve_neighbors(db_state, from, edge, depth, node_var, ctx), None)
    types.CycleDetect(edge, cycle_var) -> 
      #(solve_cycle_detect(db_state, edge, cycle_var, ctx), None)
    types.BetweennessCentrality(edge, entity_var, score_var) -> 
      #(solve_betweenness(db_state, edge, entity_var, score_var, ctx), None)
    types.TopologicalSort(edge, entity_var, order_var) -> 
      #(solve_topological_sort(db_state, edge, entity_var, order_var, ctx), None)
    types.StronglyConnectedComponents(edge, entity_var, component_var) -> 
      #(solve_strongly_connected(db_state, edge, entity_var, component_var, ctx), None)
    types.StartsWith(var, prefix) -> 
      #(solve_starts_with(db_state, var, prefix, ctx), None)
    types.BloomJoin(variable, clauses) -> 
      solve_bloom_join(db_state, variable, clauses, ctx, rules, as_of_tx, as_of_valid)
    types.Pull(var, entity, pattern) -> {
      case resolve_part(entity, ctx) {
        Some(fact.Ref(eid)) -> {
          let res = pull(db_state, fact.Uid(eid), pattern)
          #([dict.insert(ctx, var, pull_result_to_value(res))], None)
        }
        Some(fact.Int(eid_int)) -> {
          let res = pull(db_state, fact.Uid(fact.EntityId(eid_int)), pattern)
          #([dict.insert(ctx, var, pull_result_to_value(res))], None)
        }
        _ -> #([], None)
      }
    }
    types.BloomFilter(var, filter) -> {
      case dict.get(ctx, var) {
        Ok(val) -> {
          let s = fact.to_string(val)
          case bloom.might_contain(filter, s) {
            True -> #([ctx], None)
            False -> #([], None)
          }
        }
        _ -> #([ctx], None)
      }
    }
    _ -> #([ctx], None)
  }
}

fn solve_positive_with_state(
  db_state: types.DbState,
  triple: types.Clause,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(List(Dict(String, fact.Value)), Option(Dict(String, List(fact.ColumnChunk)))) {
  let #(e_p, attr, v_p) = triple
  let e_val = resolve_part(e_p, ctx)
  let v_val = resolve_part(v_p, ctx)

  // 1. Check if we should use Cracking (Columnar layout + range query)
  // For now, we'll implement JIT partitioning if it's columnar.
  let #(base_datoms, new_store) = case dict.get(db_state.columnar_store, attr) {
    Ok(chunks) -> {
       // If we have a constant value v_val, we can refine the index
       let updated_chunks = case v_val {
         Some(v) -> {
           list.map(chunks, fn(chunk) {
             let new_values = cracking.partition(chunk.values, v)
             fact.ColumnChunk(..chunk, values: new_values)
           })
         }
         None -> chunks
       }
       
       // Convert chunks back to datoms for the solver (standard path)
       // Future: specialized columnar solver
       let datoms = vectorized.chunks_to_datoms(updated_chunks)
       #(datoms, Some(dict.from_list([#(attr, updated_chunks)])))
    }
    Error(_) -> {
      let memory_datoms = case e_val, v_val {
        Some(fact.Ref(fact.EntityId(e))), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, fact.EntityId(e), attr, v)
        Some(fact.Ref(fact.EntityId(e))), None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
        Some(fact.Int(e)), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, fact.EntityId(e), attr, v)
        Some(fact.Int(e)), None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
        None, Some(v) -> index.get_datoms_by_val(db_state.aevt, attr, v)
        None, None -> index.get_all_datoms_for_attr(db_state.eavt, attr)
        Some(_), _ -> []
      }
      
      let disk_datoms = case db_state.ets_name {
        Some(name) -> {
          case e_val, v_val {
            Some(fact.Ref(fact.EntityId(e))), Some(v) -> 
               ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e)) |> list.filter(fn(d: fact.Datom) { d.attribute == attr && d.value == v })
            Some(fact.Ref(fact.EntityId(e))), None -> 
               ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e)) |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
            Some(fact.Int(e)), Some(v) -> 
               ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e)) |> list.filter(fn(d: fact.Datom) { d.attribute == attr && d.value == v })
            Some(fact.Int(e)), None -> 
               ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e)) |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
            None, Some(v) -> 
               ets_index.lookup_datoms(name <> "_aevt", attr) |> list.filter(fn(d: fact.Datom) { d.value == v })
            None, None -> 
               ets_index.lookup_datoms(name <> "_aevt", attr)
            Some(_), _ -> []
          }
        }
        None -> []
      }
      
      let datoms = list.append(memory_datoms, disk_datoms)
      #(datoms, None)
    }
  }

  let active = base_datoms 
    |> filter_by_time(as_of_tx, as_of_valid)
    |> filter_active()

  // Morsel-driven execution:
  // If we have contexts to evaluate against, run them through morsel workers
  // Chunk size is determined by config, defaulting to 1000 if not set
  let results = morsel.execute_morsels(
    active,
    [ctx],
    e_p,
    v_p,
    db_state.config.batch_size
  )
  
  #(results, new_store)
}

fn solve_positive(
  db_state: types.DbState,
  triple: types.Clause,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  solve_positive_with_state(db_state, triple, ctx, as_of_tx, as_of_valid).0
}

fn solve_negative(
  db_state: types.DbState,
  triple: types.Clause,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case solve_positive(db_state, triple, ctx, as_of_tx, as_of_valid) {
    [] -> [ctx]
    _ -> []
  }
}

fn solve_clause_with_derived(
  db_state: types.DbState,
  clause: types.BodyClause,
  ctx: Dict(String, fact.Value),
  all_derived: Set(fact.Datom),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(List(Dict(String, fact.Value)), Option(Dict(String, List(fact.ColumnChunk)))) {
  case clause {
    types.Positive(trip) -> #(solve_triple_with_derived(db_state, trip, ctx, all_derived, as_of_tx, as_of_valid), None)
    types.Negative(trip) -> {
      case solve_triple_with_derived(db_state, trip, ctx, all_derived, as_of_tx, as_of_valid) {
        [] -> #([ctx], None)
        _ -> #([], None)
      }
    }
    _ -> solve_clause(db_state, clause, ctx, db_state.stored_rules, as_of_tx, as_of_valid)
  }
}

fn solve_triple_with_derived(
  db_state: types.DbState,
  triple: types.Clause,
  ctx: Dict(String, fact.Value),
  derived: Set(fact.Datom),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  let #(e_p, attr, v_p) = triple
  let e_val = resolve_part(e_p, ctx)
  let v_val = resolve_part(v_p, ctx)

  let base_datoms = case db_state.ets_name {
    Some(name) -> {
      case e_val, v_val {
        Some(fact.Ref(fact.EntityId(e))), Some(v) -> {
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) { d.attribute == attr && d.value == v })
        }
        Some(fact.Ref(fact.EntityId(e))), None -> {
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
        }
        Some(fact.Int(e)), Some(v) -> {
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) { d.attribute == attr && d.value == v })
        }
        Some(fact.Int(e)), None -> {
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
        }
        None, Some(v) -> {
          ets_index.lookup_datoms(name <> "_aevt", attr)
          |> list.filter(fn(d: fact.Datom) { d.value == v })
        }
        None, None -> {
          ets_index.lookup_datoms(name <> "_aevt", attr)
        }
        Some(_), _ -> []
      }
    }
    None -> {
      case e_val, v_val {
        Some(fact.Ref(fact.EntityId(e))), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, fact.EntityId(e), attr, v)
        Some(fact.Ref(fact.EntityId(e))), None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
        Some(fact.Int(e)), Some(v) -> index.get_datoms_by_entity_attr_val(db_state.eavt, fact.EntityId(e), attr, v)
        Some(fact.Int(e)), None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
        None, Some(v) -> index.get_datoms_by_val(db_state.aevt, attr, v)
        None, None -> index.get_all_datoms_for_attr(db_state.eavt, attr)
        Some(_), _ -> []
      }
    }
  }

  let derived_datoms = set.to_list(derived) 
    |> list.filter(fn(d) {
      let attr_match = d.attribute == attr
      let e_match = case e_val { 
        Some(fact.Ref(fact.EntityId(e))) -> {
          let fact.EntityId(eid_int) = d.entity
          eid_int == e
        }
        Some(fact.Int(e)) -> {
          let fact.EntityId(eid_int) = d.entity
          eid_int == e
        }
        _ -> True 
      }
      let v_match = case v_val { 
        Some(v) -> d.value == v 
        _ -> True 
      }
      attr_match && e_match && v_match
    })

  let all = list.append(base_datoms, derived_datoms)
  
  let active = all
    |> filter_by_time(as_of_tx, as_of_valid)
    |> filter_active()

  list.map(active, fn(d: fact.Datom) {
    let b = ctx
    let b = case e_p { 
      types.Var(n) -> {
        let id_val = fact.Ref(d.entity)
        dict.insert(b, n, id_val)
      }
      _ -> b 
    }
    let b = case v_p { 
      types.Var(n) -> dict.insert(b, n, d.value)
      _ -> b 
    }
    b
  })
}

fn filter_active(datoms: List(fact.Datom)) -> List(fact.Datom) {
  let latest = list.fold(datoms, dict.new(), fn(acc, d) {
    let key = #(d.entity, d.attribute, d.value)
    case dict.get(acc, key) {
      Ok(#(tx, tx_idx, _op)) -> {
        case tx > d.tx || { tx == d.tx && tx_idx > d.tx_index } {
          True -> acc
          False -> dict.insert(acc, key, #(d.tx, d.tx_index, d.operation))
        }
      }
      _ -> dict.insert(acc, key, #(d.tx, d.tx_index, d.operation))
    }
  })
  
  list.filter(datoms, fn(d: fact.Datom) {
    let key = #(d.entity, d.attribute, d.value)
    case dict.get(latest, key) {
      Ok(#(tx, tx_idx, op)) -> tx == d.tx && tx_idx == d.tx_index && op == fact.Assert
      _ -> False
    }
  })
  |> list.unique()
}

fn resolve_part(part: types.Part, ctx: Dict(String, fact.Value)) -> Option(fact.Value) {
  case part {
    types.Var(name) -> option.from_result(dict.get(ctx, name))
    types.Val(val) -> Some(val)
  }
}

fn resolve_part_optional(part: types.Part, ctx: Dict(String, fact.Value)) -> Option(fact.Value) {
  case part {
    types.Var(name) -> option.from_result(dict.get(ctx, name))
    types.Val(val) -> Some(val)
  }
}

fn do_solve_clauses(
  db_state: types.DbState,
  clauses: List(types.BodyClause),
  rules: List(types.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  contexts: List(Dict(String, fact.Value)),
  initial_store: Option(Dict(String, List(fact.ColumnChunk))),
) -> #(List(Dict(String, fact.Value)), Option(Dict(String, List(fact.ColumnChunk)))) {
  case clauses {
    [] -> #(contexts, initial_store)
    [first, ..rest] -> {
      let #(next_contexts, next_store) = case list.length(contexts) > db_state.config.parallel_threshold {
        True -> {
          // Parallel path
          let subject = process.new_subject()
          process.spawn(fn() {
            let res = list.fold(contexts, #([], initial_store), fn(acc, ctx) {
              let #(acc_ctxs, acc_store) = acc
              let #(new_ctxs, clause_store) = solve_clause(db_state, first, ctx, rules, as_of_tx, as_of_valid)
              #(list.append(acc_ctxs, new_ctxs), merge_optional_stores(acc_store, clause_store))
            })
            process.send(subject, res)
          })
          let assert Ok(res) = process.receive(subject, 60000)
          res
        }
        False -> {
          list.fold(contexts, #([], initial_store), fn(acc, ctx) {
            let #(acc_ctxs, acc_store) = acc
            let #(new_ctxs, clause_store) = solve_clause(db_state, first, ctx, rules, as_of_tx, as_of_valid)
            #(list.append(acc_ctxs, new_ctxs), merge_optional_stores(acc_store, clause_store))
          })
        }
      }
      do_solve_clauses(db_state, rest, rules, as_of_tx, as_of_valid, next_contexts, next_store)
    }
  }
}

fn solve_aggregate(
  ctx: Dict(String, fact.Value),
  var: String,
  func: types.AggFunc,
  target_var: String,
  db_state: types.DbState,
  clauses: List(types.BodyClause),
  rules: List(types.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(List(Dict(String, fact.Value)), Option(Dict(String, List(fact.ColumnChunk)))) {
  // Phase 55: HTAP Optimized Aggregate
  let config = dict.get(db_state.schema, target_var) 
    |> result.unwrap(fact.AttributeConfig(unique: False, component: False, retention: fact.All, cardinality: fact.Many, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  
  case config.layout, clauses {
    fact.Columnar, filters -> {
      // Optimized Columnar Aggregate
      let chunks = dict.get(db_state.columnar_store, target_var) |> result.unwrap([])
      
      // Phase 56: JIT Cracking
      // Search for cracking candidates in filters
      let cracking_pivots = list.filter_map(filters, fn(c) {
        case c {
          types.Filter(types.Gt(types.Var(v), types.Val(p))) if v == target_var -> Ok(p)
          types.Filter(types.Lt(types.Var(v), types.Val(p))) if v == target_var -> Ok(p)
          _ -> Error(Nil)
        }
      })
      
      let #(updated_chunks, was_cracked) = case cracking_pivots {
        [pivot, ..] -> {
          let nc = list.map(chunks, fn(c) { cracking.crack_chunk(c, pivot) })
          #(nc, True)
        }
        _ -> #(chunks, False)
      }
      
      // Calculate Aggregate
      let agg_val = case func {
        types.Sum -> fact.Float(list.fold(updated_chunks, 0.0, fn(acc, c) { acc +. vectorized.sum_column(c) }))
        types.Avg -> {
           let total_sum = list.fold(updated_chunks, 0.0, fn(acc, c) { acc +. vectorized.sum_column(c) })
           let total_count = list.fold(updated_chunks, 0, fn(acc, c) { acc + vectorized.count_node(c.values) })
           case total_count {
             0 -> fact.Float(0.0)
             _ -> fact.Float(total_sum /. int.to_float(total_count))
           }
        }
        _ -> {
          let target_values = get_aggregate_values_row_based(db_state, clauses, rules, as_of_tx, as_of_valid, ctx, target_var)
          case aggregate.aggregate(target_values, func) {
            Ok(val) -> val
            Error(_) -> fact.Int(0)
          }
        }
      }
      
      // In this Phase 56 MVP, we only support cracking on aggregates without complex join-filters
      // If there are other filters, we might still need to fallback or combine.
      // For now, if was_cracked, we note the updated state.
      
      let res_ctx = [dict.insert(ctx, var, agg_val)]
      let updated_store = case was_cracked {
        True -> Some(dict.from_list([#(target_var, updated_chunks)]))
        False -> None
      }
      #(res_ctx, updated_store)
    }
    _, _ -> {
      // Row-based or with filters
      let target_values = get_aggregate_values_row_based(db_state, clauses, rules, as_of_tx, as_of_valid, ctx, target_var)
      case aggregate.aggregate(target_values, func) {
        Ok(val) -> #([dict.insert(ctx, var, val)], None)
        Error(_) -> #([], None)
      }
    }
  }
}

fn get_aggregate_values_row_based(
  db_state: types.DbState,
  clauses: List(types.BodyClause),
  rules: List(types.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  ctx: Dict(String, fact.Value),
  target_var: String,
) -> List(fact.Value) {
  let #(sub_results, _store) = case clauses {
    [] -> #([ctx], None)
    _ -> do_solve_clauses(db_state, clauses, rules, as_of_tx, as_of_valid, [ctx], None)
  }
  
  list.filter_map(sub_results, fn(res) {
    dict.get(res, target_var)
  })
}

fn compare_values(a: fact.Value, b: fact.Value) -> order.Order {
  case a, b {
    fact.Int(i1), fact.Int(i2) -> int.compare(i1, i2)
    fact.Float(f1), fact.Float(f2) -> float.compare(f1, f2)
    fact.Str(s1), fact.Str(s2) -> string.compare(s1, s2)
    fact.Int(i), fact.Float(f) -> float.compare(int.to_float(i), f)
    fact.Float(f), fact.Int(i) -> float.compare(f, int.to_float(i))
    _, _ -> order.Eq
  }
}

fn solve_similarity(
  db_state: types.DbState,
  var: String,
  vec: List(Float),
  threshold: Float,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case dict.get(ctx, var) {
    Ok(fact.Vec(v)) -> {
      let dist = vector.cosine_similarity(vec, v)
      case dist >=. threshold {
        True -> [ctx]
        False -> []
      }
    }
    // If bound but NOT a vector, it can't match.
    Ok(_) -> []
    // Similarity as a SOURCE clause (Unbound variable)
    // Use NSW vec_index for O(log N) search, fallback to AVET if empty.
    Error(Nil) -> {
      case vec_index.size(db_state.vec_index) > 0 {
        True -> {
          // Use graph-accelerated ANN search
          let norm_vec = vector.normalize(vec)
          let results = vec_index.search(db_state.vec_index, norm_vec, threshold, 100)
          list.filter_map(results, fn(r) {
            // Find the actual datom value to ensure join compatibility
            case index.filter_by_entity(db_state.eavt, r.entity) |> list.filter(fn(d: fact.Datom) {
              case d.value {
                fact.Vec(_) -> True
                _ -> False
              }
            }) {
              [d, ..] -> Ok(dict.insert(ctx, var, d.value))
              [] -> Error(Nil)
            }
          })
        }
        False -> {
          // Fallback: brute-force AVET scan
          let matching_datoms =
            index.get_all_datoms_avet(db_state.avet)
            |> filter_by_time(as_of_tx, as_of_valid)
            |> filter_active()
            |> list.filter_map(fn(d: fact.Datom) {
              case d.value {
                fact.Vec(v) -> {
                  let dist = vector.cosine_similarity(vec, v)
                  case dist >=. threshold {
                    True -> Ok(d)
                    False -> Error(Nil)
                  }
                }
                _ -> Error(Nil)
              }
            })
          
          list.map(matching_datoms, fn(d: fact.Datom) {
            dict.insert(ctx, var, d.value)
          })
        }
      }
    }
  }
}

pub fn entity_history(db_state: types.DbState, eid: fact.EntityId) -> List(fact.Datom) {
  dict.get(db_state.eavt, eid)
  |> result.unwrap([])
  |> list.sort(fn(a, b) {
    case int.compare(a.tx, b.tx) {
      order.Eq -> {
        case a.operation, b.operation {
          fact.Retract, fact.Assert -> order.Lt
          fact.Assert, fact.Retract -> order.Gt
          _, _ -> order.Eq
        }
      }
      other -> other
    }
  })
}

pub fn pull(
  db_state: types.DbState,
  eid: fact.Eid,
  pattern: types.PullPattern,
) -> types.PullResult {
  let id = case eid {
    fact.Uid(fact.EntityId(i)) -> fact.EntityId(i)
    fact.Lookup(#(a, v)) -> {
       index.get_entity_by_av(db_state.avet, a, v) |> result.unwrap(fact.EntityId(0))
    }
  }
  
  let datoms = case db_state.ets_name {
    Some(name) -> ets_index.lookup_datoms(name <> "_eavt", id)
    None -> index.filter_by_entity(db_state.eavt, id) |> list.reverse()
  }
  
  case list.length(datoms) > db_state.config.zero_copy_threshold {
    True -> {
      case db_state.ets_name {
        Some(name) -> {
          let assert Ok(bin) = ets_index.get_raw_binary(name <> "_eavt", id)
          types.PullRawBinary(bin)
        }
        None -> {
          types.PullRawBinary(ets_index.serialize_term(datoms))
        }
      }
    }
    False -> {
      let datoms = filter_active(datoms)
      let m = list.fold(pattern, dict.new(), fn(acc, item) {
        case item {
      types.Wildcard -> {
        list.fold(datoms, acc, fn(inner_acc, d: fact.Datom) {
          dict.insert(inner_acc, d.attribute, types.PullSingle(d.value))
        })
      }
      types.Attr(name) -> {
        let values = list.filter(datoms, fn(d: fact.Datom) { d.attribute == name }) |> list.map(fn(d) { d.value })
        case values {
          [v] -> dict.insert(acc, name, types.PullSingle(v))
          [_, ..] -> dict.insert(acc, name, types.PullMany(values))
          [] -> acc
        }
      }
      types.Except(exclusions) -> {
        list.fold(datoms, acc, fn(inner_acc, d: fact.Datom) {
          case list.contains(exclusions, d.attribute) {
            True -> inner_acc
            False -> dict.insert(inner_acc, d.attribute, types.PullSingle(d.value))
          }
        })
      }
      types.Recursion(attr, depth) -> {
        case depth <= 0 {
          True -> acc
          False -> {
            let values = list.filter(datoms, fn(d: fact.Datom) { d.attribute == attr }) |> list.map(fn(d) { d.value })
            let results = list.map(values, fn(v) {
              case v {
                fact.Ref(next_id) -> {
                  pull(db_state, fact.Uid(next_id), [types.Wildcard, types.Recursion(attr, depth - 1)])
                }
                fact.Int(next_id_int) -> {
                  pull(db_state, fact.Uid(fact.EntityId(next_id_int)), [types.Wildcard, types.Recursion(attr, depth - 1)])
                }
                _ -> types.PullSingle(v)
              }
            })
            case results {
              [r] -> dict.insert(acc, attr, r)
              [_, ..] -> dict.insert(acc, attr, types.PullNestedMany(results))
              [] -> acc
            }
          }
        }
      }
      types.Nested(name, sub_pattern) -> {
        let values = list.filter(datoms, fn(d: fact.Datom) { d.attribute == name }) |> list.map(fn(d) { d.value })
        case values {
          [fact.Ref(eid)] -> {
            let res = pull(db_state, fact.Uid(eid), sub_pattern)
            dict.insert(acc, name, res)
          }
          [fact.Int(sub_id)] -> {
            let res = pull(db_state, fact.Uid(fact.EntityId(sub_id)), sub_pattern)
            dict.insert(acc, name, res)
          }
          [_, ..] -> {
            let res_list = list.map(values, fn(v) {
              case v {
                fact.Ref(eid) -> pull(db_state, fact.Uid(eid), sub_pattern)
                fact.Int(sub_id) -> pull(db_state, fact.Uid(fact.EntityId(sub_id)), sub_pattern)
                _ -> types.PullSingle(v)
              }
            })
            case res_list {
              [r] -> dict.insert(acc, name, r)
              [_, ..] -> dict.insert(acc, name, types.PullNestedMany(res_list))
              _ -> acc
            }
          }
          _ -> acc
        }
      }
    }
  })
  types.PullMap(m)
    }
  }
}

pub fn pull_result_to_value(res: types.PullResult) -> fact.Value {
  case res {
    types.PullSingle(v) -> v
    types.PullMany(vs) -> fact.List(vs)
    types.PullNestedMany(res_list) -> fact.List(list.map(res_list, pull_result_to_value))
    types.PullMap(m) -> {
      fact.Map(dict.map_values(m, fn(_, v) { pull_result_to_value(v) }))
    }
    types.PullRawBinary(bin) -> fact.Blob(bin)
  }
}

pub fn traverse(
  db_state: types.DbState,
  start_id: Int,
  expr: types.TraversalExpr,
  max_depth: Int
) -> Result(List(fact.Value), String) {
  case list.length(expr) > max_depth {
    True -> Error("DepthLimitExceeded")
    False -> {
      let result_eids = do_traverse(db_state, [start_id], expr)
      Ok(list.map(result_eids, fn(id) { fact.Ref(fact.EntityId(id)) }))
    }
  }
}

fn do_traverse(db_state: types.DbState, current_ids: List(Int), expr: types.TraversalExpr) -> List(Int) {
  case expr {
    [] -> current_ids
    [step, ..rest] -> {
      let next_ids = list.fold(current_ids, [], fn(acc, id) {
        let step_results = case step {
          types.Out(attr) -> {
            let datoms = case db_state.ets_name {
              Some(name) -> ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(id))
                            |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
              None -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(id), attr)
            }
            let active = filter_active(datoms)
            list.filter_map(active, fn(d) {
              case d.value {
                fact.Ref(fact.EntityId(v_id)) -> Ok(v_id)
                fact.Int(v_id) -> Ok(v_id)
                _ -> Error(Nil)
              }
            })
          }
          types.In(attr) -> {
            let datoms = case db_state.ets_name {
              Some(name) -> ets_index.lookup_datoms(name <> "_aevt", attr)
                           |> list.filter(fn(d: fact.Datom) { 
                             case d.value {
                               fact.Ref(fact.EntityId(v_id)) -> v_id == id
                               fact.Int(v_id) -> v_id == id
                               _ -> False
                             }
                           })
              None -> index.get_datoms_by_val(db_state.aevt, attr, fact.Ref(fact.EntityId(id)))
            }
            let active = filter_active(datoms)
            list.map(active, fn(d) {
              let fact.EntityId(e) = d.entity
              e
            })
          }
        }
        list.append(step_results, acc)
      }) |> list.unique()
      
      do_traverse(db_state, next_ids, rest)
    }
  }
}

fn solve_temporal(
  db_state: types.DbState,
  var: String,
  e_p: types.Part,
  attr: String,
  start: Int,
  end: Int,
  basis: types.TemporalType,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let e_val = resolve_part(e_p, ctx)
  
  let base_datoms = case e_val {
    Some(fact.Ref(fact.EntityId(e))) -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
    Some(fact.Int(e)) -> index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
    _ -> []
  }

  base_datoms
  |> filter_active()
  |> list.filter(fn(d) { 
    let time = case basis {
      types.Tx -> d.tx
      types.Valid -> d.valid_time
    }
    time >= start && time <= end 
  })
  |> list.map(fn(d) {
    dict.insert(ctx, var, d.value)
  })
}



fn compile_predicate(expr: types.Expression) -> fn(Dict(String, fact.Value)) -> Bool {
  case expr {
    types.Eq(a, b) -> {
      fn(ctx) {
        let val_a = resolve_part_optional(a, ctx)
        let val_b = resolve_part_optional(b, ctx)
        val_a == val_b && option.is_some(val_a)
      }
    }
    types.Neq(a, b) -> {
      fn(ctx) {
        let val_a = resolve_part_optional(a, ctx)
        let val_b = resolve_part_optional(b, ctx)
        val_a != val_b
      }
    }
    types.Gt(a, b) -> {
      fn(ctx) {
        let val_a = resolve_part_optional(a, ctx) |> option.unwrap(fact.Int(0))
        let val_b = resolve_part_optional(b, ctx) |> option.unwrap(fact.Int(0))
        compare_values(val_a, val_b) == order.Gt
      }
    }
    types.Lt(a, b) -> {
      fn(ctx) {
        let val_a = resolve_part_optional(a, ctx) |> option.unwrap(fact.Int(0))
        let val_b = resolve_part_optional(b, ctx) |> option.unwrap(fact.Int(0))
        compare_values(val_a, val_b) == order.Lt
      }
    }
    types.And(l, r) -> {
      let compiled_l = compile_predicate(l)
      let compiled_r = compile_predicate(r)
      fn(ctx) { compiled_l(ctx) && compiled_r(ctx) }
    }
    types.Or(l, r) -> {
      let compiled_l = compile_predicate(l)
      let compiled_r = compile_predicate(r)
      fn(ctx) { compiled_l(ctx) || compiled_r(ctx) }
    }
  }
}

fn resolve_entity_id_from_part(part: types.Part, ctx: Dict(String, fact.Value)) -> Option(fact.EntityId) {
  case resolve_part_optional(part, ctx) {
    Some(fact.Ref(eid)) -> Some(eid)
    Some(fact.Int(i)) -> Some(fact.EntityId(i))
    _ -> None
  }
}


fn solve_starts_with(
  db_state: types.DbState,
  var: String,
  prefix: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case dict.get(ctx, var) {
    Ok(val) -> {
      // Bound: Filter
      case val {
        fact.Str(s) -> {
          case string.starts_with(s, prefix) {
            True -> [ctx]
            False -> []
          }
        }
        _ -> []
      }
    }
    Error(_) -> {
      let entries = art.search_prefix_entries(db_state.art_index, prefix)
      list.map(entries, fn(entry) {
        let #(val, _eid) = entry 
        // Note: StartsWith(v, p) only binds 'v'. It doesn't bind an entity 'e'.
        // If we want 'e', we'd need a clause like Fact(e, attr, v).
        // Here we just bind 'v'.
        dict.insert(ctx, var, val)
      }) |> list.unique()
    }
  }
}

       // `search_prefix` traverses the tree and collects values.
       // In `art.gleam`, `collect_all_values` returns `List(fact.EntityId)`.
       // It doesn't yield the implementation keys (the actual strings).
       
       // Issue: The current ART implementation indexes Value -> EntityId.
       // It efficiently finds Entities.
       // But `StartsWith(var, "foo")` binds `var` to the *Value* string?
       // Typically `var` is a Value in Datalog.
       
       // If the query is:
       // `Fact(e, "name", name), StartsWith(name, "Al")`
       // We can use ART to find all Entities `e` where "name" starts with "Al".
       // But `StartsWith` is a filter on `name`.
       
       // If `name` is unbound, `StartsWith` acts as a generator?
       // Infinite generator if not restricted?
       // Usually `StartsWith` is used as a constraint on an existing bound variable or an attribute lookup.
       
       // If we want to use ART for `StartsWith`, we need to iterate the ART keys.
       // The current `art.gleam` `search_prefix` returns EntityIds, which means it found values matching.
       // But it loses the actual value string.
       // To bind `name` to "Alice", "Alan", etc., we need the keys from ART.
       
       // OPTIMIZATION:
       // For now, let's implement `StartsWith` as a filter only (requires bound variable).
       // AND if we want to support efficient lookup, we'd need a `search_prefix_keys` in ART.
       // Let's stick to Filter behavior for now, and maybe generator if simple.
       
       // Wait, if I want to use the index, I should probably expose `search_prefix_keys`.
       // Let's implement it as a Filter for now to be safe and correct.
fn solve_shortest_path(
  db_state: types.DbState,
  from: types.Part,
  to: types.Part,
  edge: String,
  path_var: String,
  cost_var: Option(String),
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let from_eid = resolve_entity_id_from_part(from, ctx)
  let to_eid = resolve_entity_id_from_part(to, ctx)
  
  case from_eid, to_eid {
    Some(f), Some(t) -> {
      case graph.shortest_path(db_state, f, t, edge) {
        Some(path) -> {
          let path_val = fact.List(list.map(path, fact.Ref))
          let ctx = dict.insert(ctx, path_var, path_val)
          let ctx = case cost_var {
            Some(cv) -> dict.insert(ctx, cv, fact.Int(list.length(path) - 1))
            None -> ctx
          }
          [ctx]
        }
        None -> []
      }
    }
    _, _ -> []
  }
}

fn solve_pagerank(
  db_state: types.DbState,
  entity_var: String,
  edge: String,
  rank_var: String,
  damping: Float,
  iterations: Int,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let ranks = graph.pagerank(db_state, edge, damping, iterations)
  
  case dict.get(ctx, entity_var) {
    Ok(fact.Ref(eid)) -> {
      case dict.get(ranks, eid) {
        Ok(rank) -> [dict.insert(ctx, rank_var, fact.Float(rank))]
        Error(_) -> []
      }
    }
    Ok(fact.Int(eid_int)) -> {
      let eid = fact.EntityId(eid_int)
      case dict.get(ranks, eid) {
        Ok(rank) -> [dict.insert(ctx, rank_var, fact.Float(rank))]
        Error(_) -> []
      }
    }
    Error(_) -> {
      // Unbound, generate all
      dict.fold(ranks, [], fn(acc, eid, rank) {
        let new_ctx = dict.insert(ctx, entity_var, fact.Ref(eid))
        let new_ctx = dict.insert(new_ctx, rank_var, fact.Float(rank))
        [new_ctx, ..acc]
      })
    }
    _ -> []
  }
}

fn solve_reachable(
  db_state: types.DbState,
  from: types.Part,
  edge: String,
  node_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let from_eid = resolve_entity_id_from_part(from, ctx)
  case from_eid {
    Some(eid) -> {
      let nodes = graph.reachable(db_state, eid, edge)
      list.map(nodes, fn(n) {
        dict.insert(ctx, node_var, fact.Ref(n))
      })
    }
    None -> []
  }
}

fn solve_connected_components(
  db_state: types.DbState,
  edge: String,
  entity_var: String,
  component_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let components = graph.connected_components(db_state, edge)
  case dict.get(ctx, entity_var) {
    Ok(fact.Ref(eid)) -> {
      case dict.get(components, eid) {
        Ok(cid) -> [dict.insert(ctx, component_var, fact.Int(cid))]
        Error(_) -> []
      }
    }
    Ok(fact.Int(eid_int)) -> {
      let eid = fact.EntityId(eid_int)
      case dict.get(components, eid) {
        Ok(cid) -> [dict.insert(ctx, component_var, fact.Int(cid))]
        Error(_) -> []
      }
    }
    Error(_) -> {
      // Unbound entity — generate all nodes with their component IDs
      dict.fold(components, [], fn(acc, eid, cid) {
        let new_ctx = dict.insert(ctx, entity_var, fact.Ref(eid))
        let new_ctx = dict.insert(new_ctx, component_var, fact.Int(cid))
        [new_ctx, ..acc]
      })
    }
    _ -> []
  }
}

fn solve_neighbors(
  db_state: types.DbState,
  from: types.Part,
  edge: String,
  depth: Int,
  node_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let from_eid = resolve_entity_id_from_part(from, ctx)
  case from_eid {
    Some(eid) -> {
      let nodes = graph.neighbors_khop(db_state, eid, edge, depth)
      list.map(nodes, fn(n) {
        dict.insert(ctx, node_var, fact.Ref(n))
      })
    }
    None -> []
  }
}

fn solve_strongly_connected(
  db_state: types.DbState,
  edge: String,
  entity_var: String,
  component_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let components = graph.strongly_connected_components(db_state, edge)
  case dict.get(ctx, entity_var) {
    Ok(fact.Ref(eid)) -> {
      case dict.get(components, eid) {
        Ok(cid) -> [dict.insert(ctx, component_var, fact.Int(cid))]
        Error(_) -> []
      }
    }
    Ok(fact.Int(eid_int)) -> {
      let eid = fact.EntityId(eid_int)
      case dict.get(components, eid) {
        Ok(cid) -> [dict.insert(ctx, component_var, fact.Int(cid))]
        Error(_) -> []
      }
    }
    Error(_) -> {
      dict.fold(components, [], fn(acc, eid, cid) {
        let new_ctx = dict.insert(ctx, entity_var, fact.Ref(eid))
        let new_ctx = dict.insert(new_ctx, component_var, fact.Int(cid))
        [new_ctx, ..acc]
      })
    }
    _ -> []
  }
}

fn solve_cycle_detect(
  db_state: types.DbState,
  edge: String,
  cycle_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let cycles = graph.cycle_detect(db_state, edge)
  list.map(cycles, fn(cycle) {
    let cycle_val = fact.List(list.map(cycle, fact.Ref))
    dict.insert(ctx, cycle_var, cycle_val)
  })
}

fn solve_betweenness(
  db_state: types.DbState,
  edge: String,
  entity_var: String,
  score_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let scores = graph.betweenness_centrality(db_state, edge)
  case dict.get(ctx, entity_var) {
    Ok(fact.Ref(eid)) -> {
      case dict.get(scores, eid) {
        Ok(score) -> [dict.insert(ctx, score_var, fact.Float(score))]
        Error(_) -> []
      }
    }
    Ok(fact.Int(eid_int)) -> {
      let eid = fact.EntityId(eid_int)
      case dict.get(scores, eid) {
        Ok(score) -> [dict.insert(ctx, score_var, fact.Float(score))]
        Error(_) -> []
      }
    }
    Error(_) -> {
      // Unbound — generate all
      dict.fold(scores, [], fn(acc, eid, score) {
        let new_ctx = dict.insert(ctx, entity_var, fact.Ref(eid))
        let new_ctx = dict.insert(new_ctx, score_var, fact.Float(score))
        [new_ctx, ..acc]
      })
    }
    _ -> []
  }
}

fn solve_topological_sort(
  db_state: types.DbState,
  edge: String,
  entity_var: String,
  order_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case graph.topological_sort(db_state, edge) {
    Ok(ordered) -> {
      list.index_map(ordered, fn(node, idx) {
        let new_ctx = dict.insert(ctx, entity_var, fact.Ref(node))
        dict.insert(new_ctx, order_var, fact.Int(idx))
      })
    }
    Error(_cycle_nodes) -> {
      // Graph has cycles — return empty (no valid ordering)
      []
    }
  }
}

fn solve_virtual(
  db_state: types.DbState,
  predicate: String,
  args: List(types.Part),
  outputs: List(String),
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let resolved_args = list.try_map(args, fn(arg) {
    resolve_part_optional(arg, ctx) 
    |> option.to_result(Nil)
  })
  
  case resolved_args {
    Ok(vals) -> {
      case dict.get(db_state.virtual_predicates, predicate) {
        Ok(adapter) -> {
          let rows = adapter(vals)
          list.filter_map(rows, fn(row) {
             bind_virtual_outputs(ctx, outputs, row)
          })
        }
        Error(_) -> []
      }
    }
    Error(_) -> []
  }
}

fn bind_virtual_outputs(
  ctx: Dict(String, fact.Value),
  outputs: List(String),
  row: List(fact.Value),
) -> Result(Dict(String, fact.Value), Nil) {
  case list.length(outputs) == list.length(row) {
    True -> {
      list.zip(outputs, row)
      |> list.try_fold(ctx, fn(acc, pair) {
        let #(var, val) = pair
        case dict.get(acc, var) {
          Ok(existing) -> case existing == val {
            True -> Ok(acc)
            False -> Error(Nil)
          }
          Error(_) -> Ok(dict.insert(acc, var, val))
        }
      })
    }
    False -> Error(Nil)
  }
}

pub fn diff(db_state: types.DbState, from_tx: Int, to_tx: Int) -> List(fact.Datom) {
  index.get_all_datoms(db_state.eavt)
  |> list.filter(fn(d) { d.tx > from_tx && d.tx <= to_tx })
}

pub fn explain(clauses: List(types.BodyClause)) -> String {
  navigator.explain(clauses)
}

pub fn filter_by_time(
  datoms: List(fact.Datom),
  tx_limit: Option(Int),
  valid_limit: Option(Int),
) -> List(fact.Datom) {
  datoms
  |> list.filter(fn(d) {
    let tx_ok = case tx_limit {
      Some(tx) if tx >= 0 -> d.tx <= tx
      Some(tx) -> d.tx >= int.absolute_value(tx)
      None -> True
    }
    let valid_ok = case valid_limit {
      Some(vt) if vt >= 0 -> d.valid_time <= vt
      Some(vt) -> d.valid_time >= int.absolute_value(vt)
      None -> True
    }
    tx_ok && valid_ok
  })
}
fn solve_custom_index(
  db_state: types.DbState,
  var: String,
  index_name: String,
  query: types.IndexQuery,
  threshold: Float,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case dict.get(db_state.extensions, index_name) {
    Ok(instance) -> {
      case dict.get(db_state.registry, instance.adapter_name) {
        Ok(adapter) -> {
          let results = adapter.search(instance.data, query, threshold)
          list.filter_map(results, fn(eid) {
            let val = fact.Ref(eid)
             case dict.get(ctx, var) {
               Ok(existing) if existing == val -> Ok(ctx)
               Ok(_) -> Error(Nil)
               Error(Nil) -> Ok(dict.insert(ctx, var, val))
             }
          })
        }
        Error(_) -> []
      }
    }
    Error(_) -> []
  }
}

fn solve_similarity_entity(
  db_state: types.DbState,
  var: String,
  vec: List(Float),
  threshold: Float,
  ctx: Dict(String, fact.Value),
  _as_of_tx: Option(Int),
  _as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case vec_index.size(db_state.vec_index) > 0 {
    True -> {
      let norm_vec = vector.normalize(vec)
      let results = vec_index.search(db_state.vec_index, norm_vec, threshold, 100)
      list.filter_map(results, fn(r) {
        let val = fact.Ref(r.entity)
        case dict.get(ctx, var) {
          Ok(existing) if existing == val -> Ok(ctx)
          Ok(_) -> Error(Nil)
          Error(Nil) -> Ok(dict.insert(ctx, var, val))
        }
      })
    }
    False -> [] // Fallback to scan not implemented for Entity binding yet, relying on index
  }
}

