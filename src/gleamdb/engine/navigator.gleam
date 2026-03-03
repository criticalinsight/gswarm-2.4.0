import gleam/list
import gleam/int
import gleam/set.{type Set}
import gleam/option.{Some, None}
import gleam/string
import gleamdb/fact
import gleamdb/shared/types.{type BodyClause, type Part, Var, Val, Positive, Negative, Filter, Bind, Aggregate, Similarity, Temporal, Limit, Offset, OrderBy, GroupBy, ShortestPath, PageRank, Virtual, StartsWith}

pub fn plan(clauses: List(BodyClause)) -> List(BodyClause) {
  let #(control, data) = list.partition(clauses, is_control_clause)
  let ordered_data = greedy_reorder(data, set.new())
  list.append(ordered_data, control)
}

pub fn explain(clauses: List(BodyClause)) -> String {
  let planned = plan(clauses)
  list.map(planned, fn(c) { "  - " <> clause_to_string(c) })
  |> list.prepend("Query Plan:")
  |> list.intersperse("\n")
  |> list.fold("", fn(acc, s) { acc <> s })
}

fn is_control_clause(clause: BodyClause) -> Bool {
  case clause {
    Limit(_) | Offset(_) | OrderBy(_, _) | GroupBy(_) -> True
    _ -> False
  }
}

fn greedy_reorder(remaining: List(BodyClause), bound_vars: Set(String)) -> List(BodyClause) {
  case remaining {
    [] -> []
    _ -> {
      let #(best, others) = find_best_clause(remaining, bound_vars)
      let clause_vars = get_clause_vars(best)
      let next_bound = set.union(bound_vars, clause_vars)
      [best, ..greedy_reorder(others, next_bound)]
    }
  }
}

fn find_best_clause(clauses: List(BodyClause), bound_vars: Set(String)) -> #(BodyClause, List(BodyClause)) {
  let scored = list.map(clauses, fn(c) { #(c, estimate_cost(c, bound_vars)) })
  let sorted = list.sort(scored, fn(a, b) { int.compare(a.1, b.1) })
  
  case sorted {
    [#(best, _), ..rest] -> #(best, list.map(rest, fn(pair) { pair.0 }))
    _ -> panic as "Empty clause list in find_best_clause"
  }
}

fn estimate_cost(clause: BodyClause, bound_vars: Set(String)) -> Int {
  case clause {
    Positive(#(e, _a, v)) -> {
       let e_bound = is_part_bound(e, bound_vars)
       let v_bound = is_part_bound(v, bound_vars)
       case e_bound, v_bound {
         True, True -> 1    // Fully bound: filter
         True, False -> 10  // E bound: index lookup
         False, True -> 100 // V bound: reverse index lookup
         False, False -> 1000 // Unbound: scan
       }
    }
    Negative(_) -> 5000 // Solve negatives late
    Filter(expr) -> {
      let expr_vars = get_expr_vars(expr)
      let all_bound = set.fold(expr_vars, True, fn(acc, v) { acc && set.contains(bound_vars, v) })
      case all_bound {
        True -> 2 // Selective filter
        False -> 8000 // Blocked
      }
    }
    Bind(_, _) -> 2 // Bindings are cheap
    Aggregate(_, _, _, sub_filter) -> 2000 + list.length(sub_filter) * 100
    Similarity(_, _, _) -> 50 // NSW lookup is fast
    Temporal(_, _, _, _, _, _) -> 150 // Temporal range scan
    ShortestPath(_, _, _, _, _) -> 500
    PageRank(_, _, _, _, _) -> 1000
    StartsWith(var, _) -> {
      case set.contains(bound_vars, var) {
        True -> 10 // Filter
        False -> 50 // Index lookup
      }
    }
    Virtual(_, args, _) -> {
      let bound_args = list.filter(args, fn(a) { is_part_bound(a, bound_vars) })
      1000 - list.length(bound_args) * 100
    }
    _ -> 9999
  }
}

fn is_part_bound(part: Part, bound_vars: Set(String)) -> Bool {
  case part {
    Val(_) -> True
    Var(name) -> set.contains(bound_vars, name)
  }
}

fn get_clause_vars(clause: BodyClause) -> Set(String) {
  case clause {
    Positive(#(e, _, v)) -> set.from_list(list.filter_map([e, v], get_var_name))
    Negative(#(e, _, v)) -> set.from_list(list.filter_map([e, v], get_var_name))
    Filter(expr) -> get_expr_vars(expr)
    Bind(var, _) -> set.from_list([var])
    Aggregate(var, _, target, filter) -> {
      let sub_vars = list.map(filter, get_clause_vars) |> list.fold(set.new(), set.union)
      set.insert(set.insert(sub_vars, var), target)
    }
    StartsWith(var, _) -> set.from_list([var])
    Similarity(var, _, _) -> set.from_list([var])
    Temporal(var, entity, _, _, _, _) -> {
      let s = set.from_list([var])
      case get_var_name(entity) {
        Ok(name) -> set.insert(s, name)
        Error(_) -> s
      }
    }
    ShortestPath(from, to, _, path_var, cost_var) -> {
      let s = set.from_list([path_var])
      let s = case cost_var { Some(cv) -> set.insert(s, cv) None -> s }
      let s = case get_var_name(from) { Ok(n) -> set.insert(s, n) Error(_) -> s }
      case get_var_name(to) { Ok(n) -> set.insert(s, n) Error(_) -> s }
    }
    PageRank(entity_var, _, rank_var, _, _) -> set.from_list([entity_var, rank_var])
    Virtual(_, args, outputs) -> {
      let arg_vars = list.filter_map(args, get_var_name) |> set.from_list()
      let output_vars = set.from_list(outputs)
      set.union(arg_vars, output_vars)
    }
    _ -> set.new()
  }
}

fn get_var_name(part: Part) -> Result(String, Nil) {
  case part {
    Var(name) -> Ok(name)
    _ -> Error(Nil)
  }
}

fn get_expr_vars(expr: types.Expression) -> Set(String) {
  case expr {
    types.Eq(a, b) | types.Neq(a, b) | types.Gt(a, b) | types.Lt(a, b) -> {
      set.from_list(list.filter_map([a, b], get_var_name))
    }
    types.And(l, r) | types.Or(l, r) -> set.union(get_expr_vars(l), get_expr_vars(r))
  }
}

fn clause_to_string(clause: BodyClause) -> String {
  // Simplified for explain output
  case clause {
    Positive(#(e, a, v)) -> "Positive(" <> part_to_string(e) <> ", " <> a <> ", " <> part_to_string(v) <> ")"
    Negative(#(e, a, v)) -> "Negative(" <> part_to_string(e) <> ", " <> a <> ", " <> part_to_string(v) <> ")"
    Filter(_) -> "Filter(...)"
    Similarity(v, _, _) -> "Similarity(" <> v <> ")"
    Temporal(v, e, a, _, _, _) -> "Temporal(" <> v <> ", " <> part_to_string(e) <> ", " <> a <> ")"
    Limit(n) -> "Limit(" <> int.to_string(n) <> ")"
    OrderBy(v, _) -> "OrderBy(" <> v <> ")"
    Virtual(p, args, outputs) -> "Virtual(" <> p <> ", count=" <> int.to_string(list.length(args)) <> ", outputs=" <> string.inspect(outputs) <> ")"
    ShortestPath(_, _, e, v, _) -> "ShortestPath(edge=" <> e <> ", var=" <> v <> ")"
    PageRank(_, e, v, _, _) -> "PageRank(edge=" <> e <> ", var=" <> v <> ")"
    _ -> "OtherClause"
  }
}

fn part_to_string(p: Part) -> String {
  case p {
    Var(n) -> "?" <> n
    Val(v) -> fact.to_string(v)
  }
}
