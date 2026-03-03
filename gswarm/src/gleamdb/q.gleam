import gleam/list
import gleam/option
import gleamdb/shared/types.{type BodyClause, Negative, Positive, Val, Var}
import gleamdb/fact

pub type QueryBuilder {
  QueryBuilder(clauses: List(BodyClause))
}

pub fn new() -> QueryBuilder {
  QueryBuilder(clauses: [])
}

pub fn select(_vars: List(String)) -> QueryBuilder {
  new()
}

/// Helper for string value
pub fn s(val: String) -> types.Part {
  Val(fact.Str(val))
}

/// Helper for int value
pub fn i(val: Int) -> types.Part {
  Val(fact.Int(val))
}

/// Helper for variable
pub fn v(name: String) -> types.Part {
  Var(name)
}

/// Helper for vector value
pub fn vec(val: List(Float)) -> types.Part {
  Val(fact.Vec(val))
}

/// Add a where clause (Entity, Attribute, Value).
pub fn where(
  builder: QueryBuilder,
  entity: types.Part,
  attr: String,
  value: types.Part,
) -> QueryBuilder {
  let clause = Positive(#(entity, attr, value))
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Add a negative where clause (Entity, Attribute, Value).
pub fn negate(
  builder: QueryBuilder,
  entity: types.Part,
  attr: String,
  value: types.Part,
) -> QueryBuilder {
  let clause = Negative(#(entity, attr, value))
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Count aggregate
pub fn count(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Count, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Sum aggregate
pub fn sum(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Sum, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Avg aggregate
pub fn avg(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Avg, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Median aggregate
pub fn median(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Median, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Min aggregate
pub fn min(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Min, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Max aggregate
pub fn max(builder: QueryBuilder, into: String, target: String, filter: List(BodyClause)) -> QueryBuilder {
  let clause = types.Aggregate(into, types.Max, target, filter)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Placeholder for similarity search
pub fn similar(
  builder: QueryBuilder,
  entity: types.Part,
  attr: String,
  vector: List(Float),
  _threshold: Float,
) -> QueryBuilder {
  let clause = Positive(#(entity, attr, Val(fact.Vec(vector))))
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Temporal range query (on Transaction Time)
pub fn temporal(
  builder: QueryBuilder,
  variable: String,
  entity: types.Part,
  attr: String,
  start: Int,
  end: Int,
) -> QueryBuilder {
  let clause = types.Temporal(variable, entity, attr, start, end, types.Tx)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Temporal range query (on Valid Time)
pub fn valid_temporal(
  builder: QueryBuilder,
  variable: String,
  entity: types.Part,
  attr: String,
  start: Int,
  end: Int,
) -> QueryBuilder {
  let clause = types.Temporal(variable, entity, attr, start, end, types.Valid)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Filter results since a specific value (exclusive)
pub fn since(builder: QueryBuilder, variable: String, val: types.Part) -> QueryBuilder {
  let clause = types.Filter(types.Gt(types.Var(variable), val))
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Limit results
pub fn limit(builder: QueryBuilder, n: Int) -> QueryBuilder {
  let clause = types.Limit(n)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Offset results
pub fn offset(builder: QueryBuilder, n: Int) -> QueryBuilder {
  let clause = types.Offset(n)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Order results
pub fn order_by(builder: QueryBuilder, variable: String, direction: types.OrderDirection) -> QueryBuilder {
  let clause = types.OrderBy(variable, direction)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Group By (Placeholder/Future)
pub fn group_by(builder: QueryBuilder, variable: String) -> QueryBuilder {
  let clause = types.GroupBy(variable)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Find the shortest path between two entities via an edge attribute.
pub fn shortest_path(
  builder: QueryBuilder,
  from: types.Part,
  to: types.Part,
  edge: String,
  path_var: String,
) -> QueryBuilder {
  let clause = types.ShortestPath(from, to, edge, path_var, option.None)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Calculate PageRank for nodes connected by an edge.
pub fn pagerank(
  builder: QueryBuilder,
  entity_var: String,
  edge: String,
  rank_var: String,
) -> QueryBuilder {
  let clause = types.PageRank(entity_var, edge, rank_var, 0.85, 20)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Query an external data source (Virtual Predicate).
pub fn virtual(
  builder: QueryBuilder,
  predicate: String,
  args: List(types.Part),
  outputs: List(String),
) -> QueryBuilder {
  let clause = types.Virtual(predicate, args, outputs)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Find all nodes reachable from a starting node via an edge attribute (transitive closure).
pub fn reachable(
  builder: QueryBuilder,
  from: types.Part,
  edge: String,
  node_var: String,
) -> QueryBuilder {
  let clause = types.Reachable(from, edge, node_var)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Label each node with a connected component ID.
pub fn connected_components(
  builder: QueryBuilder,
  edge: String,
  entity_var: String,
  component_var: String,
) -> QueryBuilder {
  let clause = types.ConnectedComponents(edge, entity_var, component_var)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Find all nodes within K hops of a starting node.
pub fn neighbors(
  builder: QueryBuilder,
  from: types.Part,
  edge: String,
  depth: Int,
  node_var: String,
) -> QueryBuilder {
  let clause = types.Neighbors(from, edge, depth, node_var)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Label each node with its strongly connected component ID (Tarjan's algorithm).
pub fn strongly_connected_components(
  builder: QueryBuilder,
  edge: String,
  entity_var: String,
  component_var: String,
) -> QueryBuilder {
  let clause = types.StronglyConnectedComponents(edge, entity_var, component_var)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Detect cycles in directed graph. Each result binds a List of entity refs forming a cycle.
pub fn cycle_detect(
  builder: QueryBuilder,
  edge: String,
  cycle_var: String,
) -> QueryBuilder {
  let clause = types.CycleDetect(edge, cycle_var)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Calculate betweenness centrality (Brandes' algorithm) for each node.
pub fn betweenness_centrality(
  builder: QueryBuilder,
  edge: String,
  entity_var: String,
  score_var: String,
) -> QueryBuilder {
  let clause = types.BetweennessCentrality(edge, entity_var, score_var)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Topological ordering of a DAG. Returns empty if cycles exist.
pub fn topological_sort(
  builder: QueryBuilder,
  edge: String,
  entity_var: String,
  order_var: String,
) -> QueryBuilder {
  let clause = types.TopologicalSort(edge, entity_var, order_var)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Generic filter expression.
pub fn filter(
  builder: QueryBuilder,
  expr: types.Expression,
) -> QueryBuilder {
  let clause = types.Filter(expr)
  QueryBuilder(clauses: list.append(builder.clauses, [clause]))
}

/// Convert builder to a list of clauses for `gleamdb.query`.
pub fn to_clauses(builder: QueryBuilder) -> List(BodyClause) {
  builder.clauses
}
