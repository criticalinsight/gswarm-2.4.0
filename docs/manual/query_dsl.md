# GleamDB Query DSL (`gleamdb/q`) 🎨

> "Querying should feel like drawing, not assembling furniture."

The `gleamdb/q` module provides a fluent, type-safe builder for constructing Datalog queries. It replaces the verbose tuple construction with a pipeline-friendly API.

## Core Concepts

### 1. Values vs Variables
Datalog logic distinguishes between fixed values (`Val`) and logical variables (`Var`).
- Use `q.v("name")` to create a **Variable** (e.g., `?name`).
- Use `q.s("string")` or `q.i(42)` to create a **Value**.

### 2. The Pipeline
Queries start with `q.select` and flow through a series of `where` (and `negate`) clauses.

## API Reference

### `q.select(vars: List(String))`
Starts a new query builder.
- **vars**: Currently implicit, but reserved for projected variables in future versions.
- **Returns**: A fresh `QueryBuilder`.

```gleam
let query = q.select(["e", "name"])
```

### `q.where(entity, attribute, value)`
Adds a **Positive** clause. Matches facts that *exist* in the database.
- **entity**: `q.v("e")` or `q.i(101)`
- **attribute**: String (e.g., `"user/email"`)
- **value**: `q.v("email")` or `q.s("alice@example.com")`

```gleam
q.where(q.v("e"), "user/role", q.s("Admin"))
```

### `q.negate(entity, attribute, value)`
Adds a **Negative** clause. Matches only if the fact does *not* exist.
- **Constraint**: All variables in a negative clause must be bound in a positive clause elsewhere in the query (Safety).

```gleam
// Find users who are NOT admins
|> q.where(q.v("e"), "user/name", q.v("name"))
|> q.negate(q.v("e"), "user/role", q.s("Admin"))
```

### 5. Advanced Predicates (Graph & Federation)
Native logic for complex traversals and external data:

- `q.shortest_path(from, to, edge, path_var)`: BFS pathfinding.
- `q.pagerank(entity_var, edge, rank_var)`: PageRank node importance.
- `q.virtual(predicate, args, outputs)`: Federated data access.

```gleam
let query = q.new()
  |> q.shortest_path(q.v("a"), q.v("b"), "route/to", "path")
  |> q.virtual("external_api", [q.v("path")], ["status"])
```

### 6. Aggregates (Phase 31)
GleamDB supports pure, distributed aggregation via the `Aggregate` clause.

- `target_var`: Name of the variable to bind the result to.
- `function`: The aggregation function (`Sum`, `Count`, `Min`, `Max`, `Avg`, `Median`).
- `source_var`: The variable to aggregate over.
- `filters`: A list of filter clauses (currently not used in the simplified API, pass `[]`).

```gleam
import gleamdb/shared/types.{Aggregate, Sum, Count}

let query = [
  // 1. Match entities having "age"
  gleamdb.p(#(types.Var("e"), "age", types.Var("val"))),
  
  // 2. Sum "val" into "total_age"
  Aggregate("total_age", Sum, "val", []),

  // 3. Count "e" into "count"
  Aggregate("count", Count, "e", [])
]
```

### Helpers
- `q.v(name)`: Creates a Variable (`Var`).
- `q.s(val)`: Creates a String Value (`Val(Str)`).
- `q.i(val)`: Creates an Int Value (`Val(Int)`).
- `q.to_clauses(builder)`: Finalizes the builder into a `List(BodyClause)` for `gleamdb.query`.

## Full Example

```gleam
import gleamdb
import gleamdb/q

pub fn find_active_admins(db: gleamdb.Db) {
  let query = q.select(["name"])
    |> q.where(q.v("e"), "user/role", q.s("Admin"))
    |> q.where(q.v("e"), "user/status", q.s("Active"))
    |> q.where(q.v("e"), "user/name", q.v("name"))
    |> q.to_clauses()

  gleamdb.query(db, query)
}
```

## Graph Traversal DSL (Phase 60)

For multi-hop relationship queries, use the `traverse` API instead of verbose Datalog:

### `gleamdb.traverse(db, eid, expr, max_depth)`
- **db**: Database subject.
- **eid**: Starting entity (`fact.uid(id)` or `fact.Lookup(#(attr, val))`).
- **expr**: `List(TraversalStep)` — a chain of `Out(attr)` and `In(attr)` hops.
- **max_depth**: Maximum allowed expression length (rejects with `DepthLimitExceeded` if exceeded).
- **Returns**: `Result(List(fact.Value), String)`.

```gleam
import gleamdb/shared/types.{Out, In}

// Find all posts liked by friends of user 1
let assert Ok(posts) = gleamdb.traverse(
  db,
  fact.uid(1),
  [Out("user/friends"), Out("user/posts")],
  5
)

// Reverse: find who likes a specific post
let assert Ok(likers) = gleamdb.traverse(
  db,
  fact.uid(42),
  [In("likes/post")],
  3
)
```

