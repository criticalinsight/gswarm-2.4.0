# Graph Algorithms (Native Predicates)

GleamDB provides **9 native graph algorithms** implemented as "Magic Predicates" within the Datalog engine. This allows for complex network analysis — cycle detection, centrality scoring, topological ordering — without leaving the logic paradigm.

## Philosophy: De-complected Traversals

1.  **Uniformity**: Every algorithm is exposed as a standard `BodyClause` variant.
2.  **Composability**: Predicates compose freely with Datalog joins, filters, and aggregates.
3.  **Index-Native**: All algorithms directly traverse `EAVT`/`AEVT` indices — no external graph database needed.
4.  **Purely Functional**: ~700 lines of immutable, recursion-based algorithms in `algo/graph.gleam`.

## Predicate Reference

| # | DSL Function | Algorithm | Complexity | Use Case |
|---|-------------|-----------|------------|----------|
| 1 | `q.shortest_path` | BFS | O(V+E) | Path finding between two nodes |
| 2 | `q.pagerank` | Iterative Power | O(V×I) | Influence/importance ranking |
| 3 | `q.reachable` | BFS flood | O(V+E) | Transitive closure from a node |
| 4 | `q.connected_components` | BFS flood-fill | O(V+E) | Undirected cluster labeling |
| 5 | `q.neighbors` | Bounded BFS | O(V+E) | K-hop neighborhood exploration |
| 6 | `q.cycle_detect` | DFS back-edge | O(V+E) | Circular dependency / wash-trade detection |
| 7 | `q.betweenness_centrality` | Brandes' | O(V×E) | Gatekeeper / broker node identification |
| 8 | `q.topological_sort` | Kahn's | O(V+E) | DAG ordering / dependency resolution |
| 9 | `q.strongly_connected_components` | Tarjan's | O(V+E) | Directed mutual-reachability clusters |

## Usage Examples

### 1. Shortest Path
```gleam
let query = q.new()
  |> q.where(q.v("start"), "city/name", q.s("London"))
  |> q.where(q.v("end"), "city/name", q.s("Paris"))
  |> q.shortest_path(q.v("start"), q.v("end"), "route/to", "path")
  |> q.to_clauses()
```

### 2. PageRank
```gleam
let query = q.new()
  |> q.pagerank("node", "link", "rank")
  |> q.order_by("rank", Desc)
  |> q.limit(10)
  |> q.to_clauses()
```

### 3. Reachable (Transitive Closure)
```gleam
let query = q.new()
  |> q.where(q.v("root"), "name", q.s("Alice"))
  |> q.reachable(q.v("root"), "follows", "reached")
  |> q.to_clauses()
```

### 4. Connected Components
```gleam
let query = q.new()
  |> q.connected_components("friend_of", "person", "cluster")
  |> q.to_clauses()
```

### 5. K-hop Neighbors
```gleam
let query = q.new()
  |> q.where(q.v("me"), "name", q.s("Bob"))
  |> q.neighbors(q.v("me"), "knows", 2, "friend")
  |> q.to_clauses()
```

### 6. Cycle Detection
```gleam
// Find circular trading patterns (wash-trade detection)
let query = q.new()
  |> q.cycle_detect("trades_with", "cycle")
  |> q.to_clauses()
```

### 7. Betweenness Centrality
```gleam
// Find gatekeeper nodes in a network
let query = q.new()
  |> q.betweenness_centrality("link", "node", "score")
  |> q.order_by("score", Desc)
  |> q.limit(5)
  |> q.to_clauses()
```

### 8. Topological Sort
```gleam
// Order build dependencies
let query = q.new()
  |> q.topological_sort("depends_on", "module", "build_order")
  |> q.order_by("build_order", Asc)
  |> q.to_clauses()
```

### 9. Strongly Connected Components (Tarjan's)
```gleam
// Find mutual-reachability clusters (trading rings, circular imports)
let query = q.new()
  |> q.strongly_connected_components("imports", "module", "scc_id")
  |> q.to_clauses()
```

## Technical Details

- **Shortest Path**: BFS with path tracking. Returns `fact.List(Ref)`.
- **PageRank**: Iterative power method (damping=0.85, 20 iterations). Returns `fact.Float`.
- **Reachable**: BFS flood from source. Includes source node in results.
- **Connected Components**: Undirected flood-fill. Each node gets an `Int` component ID.
- **Neighbors**: Depth-bounded BFS. Excludes source node from results.
- **Cycle Detect**: DFS with back-edge tracking. Returns each cycle as `fact.List(Ref)`.
- **Betweenness Centrality**: Brandes' algorithm. Returns `fact.Float` score per node.
- **Topological Sort**: Kahn's BFS-based algorithm. Returns `Int` position. Empty result if cycles exist.
- **Strongly Connected Components**: Tarjan's DFS algorithm. Returns `Int` component ID per node.

All algorithms use the shared `build_graph` infrastructure which constructs adjacency lists from the `AEVT` index.

## Graph Traversal DSL (Phase 60)

For simpler multi-hop relationship queries that don't require full Datalog, GleamDB provides a **constrained traversal DSL**:

```gleam
import gleamdb
import gleamdb/fact
import gleamdb/shared/types.{Out, In}

// Alice → friends → posts ← likes
let assert Ok(likers) = gleamdb.traverse(
  db,
  fact.uid(1),
  [Out("user/friends"), Out("user/posts"), In("likes/post")],
  5  // max_depth guard
)
```

| Step | Direction | Resolution |
|------|-----------|------------|
| `Out(attr)` | Entity → Value | Chases `Ref` values via EAVT |
| `In(attr)` | Value ← Entity | Reverse-resolves via AEVT |

- **Depth Guard**: Expressions longer than `max_depth` return `Error("DepthLimitExceeded")`.
- **Deduplication**: Results are deduplicated per hop via `list.unique()`.
- **ETS Fast-Path**: Uses ETS indices when `ets_name` is available.

